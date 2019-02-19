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
  case $2 in
    *"SNAPSHOT"*) echo $(require_property "$1" "snapshotRepository") || exit $?;;
    *) echo $(require_property "$1" "releaseRepository") || exit $?;;
  esac
}

get_current_index_json() {
  SEPARATOR="RET_CODE"
  CURL_OUTPUT=$(curl -u$1:$2 -s -w "\n$SEPARATOR%{http_code}\n" "$3") || exit $?
  RETURN_CODE="${CURL_OUTPUT##*$SEPARATOR}"
  case $RETURN_CODE in
    "200") DOWNLOADED_JSON="${CURL_OUTPUT%$SEPARATOR*}"; echo $DOWNLOADED_JSON;;
    "404") echo "{}";;
    *) exit 1
  esac
}

zip_framework() {

  rm -f "$1"
  cd "$2"
  zip -r "$1" "$3.framework"
  RESULT=$?
  cd "$OLDPWD"
  return $RESULT
}

check_artifactory_response() {
  echo "Response is: $1"
  ERROR_COUNT=$(echo $1 | jq '.errors? | length')
  if [ "$ERROR_COUNT" -gt "0" ]; then
    echo "Upload failed"
    exit 1
  fi
}

while getopts ":c:f:" opt; do
  case $opt in
    c)
      CONFIG_FILE_PATH=$OPTARG
      ;;
    f)
      FRAMEWORK_PATH=$OPTARG
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

ARTIFACTORY_URL=$(require_property "$CONFIG_FILE_PATH" "artifactoryURL") || exit $?
ARTIFACTORY_USER=$(require_gradle_property "artifactoryUser") || exit $?
ARTIFACTORY_PASSWORD=$(require_gradle_property "artifactoryPassword") || exit $?

echo "Artifactory credentials retrieved successfully"

FRAMEWORK_NAME=$(require_property "$CONFIG_FILE_PATH" "frameworkName") || exit $?
FRAMEWORK_FILE=$FRAMEWORK_PATH/$FRAMEWORK_NAME.framework
ZIPPED_FRAMEWORK_FILE="$(pwd)/$FRAMEWORK_NAME.framework.zip"
echo "Zipping framework at $FRAMEWORK_FILE into $ZIPPED_FRAMEWORK_FILE"
zip_framework "$ZIPPED_FRAMEWORK_FILE" "$FRAMEWORK_PATH" "$FRAMEWORK_NAME" || exit $?

TARGET_TYPE=$(get_build_target_type "$FRAMEWORK_FILE/$FRAMEWORK_NAME") || exit $?
echo "Target is of type $TARGET_TYPE"

VERSION_STRING=$(get_version_string "$FRAMEWORK_FILE") || exit $?
echo "Version string is $VERSION_STRING"

REPOSITORY_NAME=$(get_repository_name "$CONFIG_FILE_PATH" $VERSION_STRING) || exit $?
echo "Repository name is $REPOSITORY_NAME"

ARTIFACT_URL=$ARTIFACTORY_URL/$REPOSITORY_NAME/$TARGET_TYPE/$VERSION_STRING/$FRAMEWORK_NAME.framework.zip
JSON_URL=$ARTIFACTORY_URL/$REPOSITORY_NAME/$TARGET_TYPE/$FRAMEWORK_NAME.json

ORIGINAL_INDEX_JSON=$(get_current_index_json "$ARTIFACTORY_USER" "$ARTIFACTORY_PASSWORD" "$JSON_URL") || exit $?
JSON_VERSION=${VERSION_STRING%"-SNAPSHOT"}
UPDATED_JSON=$(echo $ORIGINAL_INDEX_JSON | jq --arg "artifactURL" "$ARTIFACT_URL" '. + {"'$JSON_VERSION'": $artifactURL}') || exit $?

echo "Updated JSON is $UPDATED_JSON"
echo "Artifact URL is $ARTIFACT_URL"
echo "JSON URL is $JSON_URL"

echo "Uploading framework to Artifactory"
ARTIFACT_MD5_CHECKSUM=$(md5 -q "$ZIPPED_FRAMEWORK_FILE")
ARTIFACT_SHA1_CHECKSUM=$(shasum -a 1 "$ZIPPED_FRAMEWORK_FILE" | awk '{ print $1 }')
CURL_OUTPUT=$(curl -u$ARTIFACTORY_USER:$ARTIFACTORY_PASSWORD -T "$ZIPPED_FRAMEWORK_FILE" --header "X-Checksum-MD5:${ARTIFACT_MD5_CHECKSUM}" --header "X-Checksum-Sha1:${ARTIFACT_SHA1_CHECKSUM}" "$ARTIFACT_URL")
rm -f "$ZIPPED_FRAMEWORK_FILE"
check_artifactory_response "$CURL_OUTPUT" || exit $?

echo "Uploading JSON to Artifactory"
JSON_MD5_CHECKSUM=$(echo $UPDATED_JSON | md5 -q)
JSON_SHA1_CHECKSUM=$(echo $UPDATED_JSON | shasum -a 1 | awk '{ print $1 }')
CURL_OUTPUT=$(echo $UPDATED_JSON | curl -u$ARTIFACTORY_USER:$ARTIFACTORY_PASSWORD -T - --header "X-Checksum-MD5:${JSON_MD5_CHECKSUM}" --header "X-Checksum-Sha1:${JSON_SHA1_CHECKSUM}" "$JSON_URL")
check_artifactory_response "$CURL_OUTPUT" || exit $?
