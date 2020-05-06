#!/usr/bin/env bash

# TODO leggere $ARCHIVE_PATH da Xcode ??

echo
echo "Archivia su Artifactory il risultato di un archive di ALCipher-Universal"
echo "Chiamare dalla cartella contenente ALChiper.xcodeproj"
echo


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

increment_ver() {
    version="$1"
    major=0
    minor=0
    build=0

    # break down the version number into it's components
    regex="([0-9]+).([0-9]+).([0-9]+)"
    if [[ $version =~ $regex ]]; then
      major="${BASH_REMATCH[1]}"
      minor="${BASH_REMATCH[2]}"
      build="${BASH_REMATCH[3]}"
    fi
    build=$(echo $build + 1 | bc)
    updated_version=${major}.${minor}.${build}
    echo $updated_version
}

# -----------------------------------------------------
# MAIN
# -----------------------------------------------------

ARTIFACTORY_USER=$(require_gradle_property "artifactoryUser") || exit $?
ARTIFACTORY_PASSWORD=$(require_gradle_property "artifactoryPassword") || exit $?
echo "Artifactory credentials retrieved successfully"

ARTIFACT_URL="https://artifactory.aliaslab.net/artifactory/SecureCallOTP_libCipher_iOS_Release"
JSON_URL=$ARTIFACT_URL/libALCipher.json
VARIANT="Release-universal"
PRODUCT="libALChiper.a.zip"
CONFIGURATION="Release"

echo "Downloading JSON from Artifactory"
ORIGINAL_INDEX_JSON=$(get_current_index_json "$ARTIFACTORY_USER" "$ARTIFACTORY_PASSWORD" "$JSON_URL") || exit $?
#echo $ORIGINAL_INDEX_JSON > orig.json
ORIGINAL_VER=$(echo $ORIGINAL_INDEX_JSON | jq 'keys[-1]')
#echo $ORIGINAL_VER
VER=$(increment_ver $ORIGINAL_VER)
echo $VER

UPDATED_JSON=$(echo $ORIGINAL_INDEX_JSON | jq --arg "artifactURL" "$ARTIFACT_URL/$VER/$PRODUCT" '. + {"'$VER'": $artifactURL}') || exit $?
echo "Updated JSON is $UPDATED_JSON"

cd build/${CONFIGURATION}-universal/ || exit $?
if [ -f $PRODUCT ]; then
        rm $PRODUCT
fi
zip -r $PRODUCT *

ARTIFACT_MD5_CHECKSUM=$(md5 -q "$PRODUCT")
ARTIFACT_SHA1_CHECKSUM=$(shasum -a 1 "$PRODUCT" | awk '{ print $1 }')

echo "Uploading framework to Artifactory"
curl -u$ARTIFACTORY_USER:$ARTIFACTORY_PASSWORD -T $PRODUCT --header "X-Checksum-MD5:${ARTIFACT_MD5_CHECKSUM}" --header "X-Checksum-Sha1:${ARTIFACT_SHA1_CHECKSUM}" "$ARTIFACT_URL/$VER/$PRODUCT"

echo "Uploading JSON to Artifactory"
JSON_MD5_CHECKSUM=$(echo $UPDATED_JSON | md5 -q)
JSON_SHA1_CHECKSUM=$(echo $UPDATED_JSON | shasum -a 1 | awk '{ print $1 }')
echo $UPDATED_JSON | curl -u$ARTIFACTORY_USER:$ARTIFACTORY_PASSWORD -T - --header "X-Checksum-MD5:${JSON_MD5_CHECKSUM}" --header "X-Checksum-Sha1:${JSON_SHA1_CHECKSUM}" "$JSON_URL"
