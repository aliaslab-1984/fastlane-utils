#!/usr/bin/env bash

require_property() {
  PROPERTY=$(cat "$1" | grep $2 | cut -d= -f2)
  if [ -z "$PROPERTY" ]; then
    echo "Property $2 not found" >&2
    exit 1
  fi
  echo $PROPERTY
}

require_gradle_property() {
  echo $(require_property ~/.gradle/gradle.properties $1)
}

get_build_target_type() {
  ARCHITECTURES=$(lipo -info "$1" | cut -d: -f3)
  if [ -z "$ARCHITECTURES" ]; then
    echo "Architectures not found" >&2
    exit 1
  fi
  case $ARCHITECTURES in
    *"x86_64"*|*"i386"*) echo "universal";;
    *) echo "ios";;
  esac
}

get_xc_version_string() {
    PLIST_JSON=$(cat "$1/Info.plist" | plutil -convert json - -o -) || exit $?
    SUB=$(echo $PLIST_JSON | jq '.AvailableLibraries[1].LibraryIdentifier' | sed -e 's/^"//' -e 's/"$//')
    SUBPATH="$1/$SUB/${FRAMEWORK_NAME}.framework"
    BUNDLE_VERSION=$(get_version_string "${SUBPATH}")
    echo $BUNDLE_VERSION
}

get_version_string() {
  PLIST_JSON=$(cat "$1/Info.plist" | plutil -convert json - -o -) || exit $?
  BUNDLE_SHORT_VERSION_STRING=$(echo $PLIST_JSON | jq '.CFBundleShortVersionString' | sed -e 's/^"//' -e 's/"$//')
  SHORT_VERSION=$(echo $BUNDLE_SHORT_VERSION_STRING | cut -d- -f1)
  VERSION_SUFFIX=$(echo $BUNDLE_SHORT_VERSION_STRING | cut -sd- -f2)
  BUNDLE_VERSION=$(echo $PLIST_JSON | jq '.CFBundleVersion' | sed -e 's/^"//' -e 's/"$//')
  if [ ! -z "$VERSION_SUFFIX" ]; then
    BUNDLE_VERSION=$BUNDLE_VERSION-$VERSION_SUFFIX
  fi
  echo $SHORT_VERSION.$BUNDLE_VERSION
}

get_repository_name() {
  if [[ "$2" == *"Debug"* ]]; then
    echo $(require_property "$1" "snapshotRepository") || exit $?
  else
    echo $(require_property "$1" "releaseRepository") || exit $?
  fi
}

get_current_index_json() {
  SEPARATOR="RET_CODE"
  CURL_OUTPUT=$(curl -u$1:$2 -s -w "\n$SEPARATOR%{http_code}\n" "$3") || exit $?
  RETURN_CODE="${CURL_OUTPUT##*$SEPARATOR}"
  case $RETURN_CODE in
    "200") DOWNLOADED_JSON="${CURL_OUTPUT%$SEPARATOR*}"; echo $DOWNLOADED_JSON;;
    "404") echo "{}";;
    *) echo "Error downloading index JSON"; exit 1
  esac
}

zip_framework() {

  rm -f "$1"
  cd "$2"
  zip -r "$1" "$3" -x \*.DS_Store
  RESULT=$?
  cd "$OLDPWD"
  return $RESULT
}

check_artifactory_response() {
  echo "Response is: $1"
  #if [ -z "$1" ]; then
  #  echo "No response from the repository"
  #  exit 1
  #fi
  if [ -z "$1" ]; then
    return
  fi
  ERROR_COUNT=$(echo $1 | jq '.errors? | length')
  if [ "$ERROR_COUNT" -gt "0" ]; then
    echo "Upload failed"
    exit 1
  fi
}

XC_PREFIX=""

while getopts ":c:f:x" opt; do
  case $opt in
    c)
      CONFIG_FILE_PATH=$OPTARG
      ;;
    f)
      FRAMEWORK_PATH=$OPTARG
      ;;
    x)
      XC_PREFIX="xc"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

if [ -z "$CONFIG_FILE_PATH" ]; then
  echo "Missing configuration file path: specify it with -c option"
  exit 1
fi

if [ -z "$FRAMEWORK_PATH" ]; then
  echo "Missing framework path: specify it with -f option"
  exit 1
fi

ARTIFACTORY_URL=$(require_gradle_property "nexusURL") || exit $?
ARTIFACTORY_USER=$(require_gradle_property "nexusUser") || exit $?
ARTIFACTORY_PASSWORD=$(require_gradle_property "nexusPassword") || exit $?

echo "Artifactory credentials retrieved successfully"

FRAMEWORK_NAME=$(require_property "$CONFIG_FILE_PATH" "frameworkName") || exit $?
FRAMEWORK_FILE="$FRAMEWORK_PATH/${FRAMEWORK_NAME}.${XC_PREFIX}framework"
ZIPPED_FRAMEWORK_FILE="$(pwd)/${FRAMEWORK_NAME}.${XC_PREFIX}framework.zip"
echo "Zipping framework at $FRAMEWORK_FILE into $ZIPPED_FRAMEWORK_FILE"
zip_framework "$ZIPPED_FRAMEWORK_FILE" "$FRAMEWORK_PATH" "$FRAMEWORK_NAME.${XC_PREFIX}framework" || exit $?

if [ -z "$XC_PREFIX" ]; then
    TARGET_TYPE=$(get_build_target_type "$FRAMEWORK_FILE/$FRAMEWORK_NAME") || exit $?
    VERSION_STRING=$(get_version_string "$FRAMEWORK_FILE") || exit $?
else
    TARGET_TYPE="xcframework"
    VERSION_STRING=$(get_xc_version_string "$FRAMEWORK_FILE") || exit $?
fi
echo "================================================================="
echo "Zipped file is $ZIPPED_FRAMEWORK_FILE"
echo "Target is of type $TARGET_TYPE"
echo "Version string is $VERSION_STRING"

REPOSITORY_NAME=$(get_repository_name "$CONFIG_FILE_PATH" "$FRAMEWORK_PATH") || exit $?
#REPOSITORY_NAME="IDSignMobileStandaloneSDK_iOS_Snapshot"
echo "Repository name is $REPOSITORY_NAME"

ARTIFACT_PATH=$ARTIFACTORY_URL/$REPOSITORY_NAME/$TARGET_TYPE/$VERSION_STRING
ARTIFACT_URL=$ARTIFACT_PATH/${FRAMEWORK_NAME}.${XC_PREFIX}framework.zip
JSON_URL=$ARTIFACTORY_URL/$REPOSITORY_NAME/$TARGET_TYPE/$FRAMEWORK_NAME.json
echo "Downloading $JSON_URL..."

ORIGINAL_INDEX_JSON=$(get_current_index_json "$ARTIFACTORY_USER" "$ARTIFACTORY_PASSWORD" "$JSON_URL") || exit $?
JSON_VERSION=${VERSION_STRING%"-SNAPSHOT"}
UPDATED_JSON=$(echo $ORIGINAL_INDEX_JSON | jq --arg "artifactURL" "$ARTIFACT_URL" '. + {"'$JSON_VERSION'": $artifactURL}') || exit $?

echo "Updated JSON is $UPDATED_JSON"
echo "Artifact URL is $ARTIFACT_URL"
echo "JSON URL is $JSON_URL"
echo "================================================================="

echo "Uploading framework to Artifactory"
MD5="${FRAMEWORK_NAME}.${XC_PREFIX}framework.zip.md5"
md5 -q "$ZIPPED_FRAMEWORK_FILE" > $MD5
SHA1="${FRAMEWORK_NAME}.${XC_PREFIX}framework.zip.sha1"
shasum -a 1 "$ZIPPED_FRAMEWORK_FILE" | awk '{ print $1 }' > $SHA1

echo " * uploading: $ZIPPED_FRAMEWORK_FILE"
echo " * to $ARTIFACT_URL"
CURL_OUTPUT=$(curl -u$ARTIFACTORY_USER:$ARTIFACTORY_PASSWORD -T "${ZIPPED_FRAMEWORK_FILE}" "$ARTIFACT_URL")
check_artifactory_response "$CURL_OUTPUT" || exit $?

CURL_OUTPUT=$(curl -u$ARTIFACTORY_USER:$ARTIFACTORY_PASSWORD -T "${MD5}" "$ARTIFACT_PATH/$MD5")
CURL_OUTPUT=$(curl -u$ARTIFACTORY_USER:$ARTIFACTORY_PASSWORD -T "${SHA1}" "$ARTIFACT_PATH/$SHA1")

echo "Uploading JSON to Artifactory"
CURL_OUTPUT=$(echo $UPDATED_JSON | curl -u$ARTIFACTORY_USER:$ARTIFACTORY_PASSWORD -T - "$JSON_URL")
# check_artifactory_response "$CURL_OUTPUT" || exit $?

rm -f "${ZIPPED_FRAMEWORK_FILE}"
rm -f "${MD5}"
rm -f "${SHA1}"
