#!/usr/bin/env bash

echo
echo "Archivia su Artifactory il risultato una build statica"
echo "Chiamare dalla cartella contenente .xcodeproj"
echo -e "\n$0 -h for more info"
echo

usage() {
	echo
	echo "Usage: $0 -h|-u|-d|-s [version]"
	echo -e "\t-u \tupload universal static library"
	echo -e "\t-d \tupload device-only static library"
	echo -e "\t-s \tupload simulator-only static library"
	echo -e "\t-h \tthis help"
	echo "if there is no version it's incremented from Artifactory's JSON"
	echo
	echo "es. $0 -d 1.0.44"
	echo
}

require_property() {
  PROPERTY=$(cat "$1" | grep $2 | cut -d= -f2)
  if [ -z "$PROPERTY" ]; then
    echo "Property $2 not found" >&2
    exit 1
  fi
  echo $PROPERTY
}

check_artifactory_response() {
  echo "Response is: $1"
  if [ -z "$1" ]; then
    echo "No response from Artifactory"
    exit 1
  fi
  ERROR_COUNT=$(echo $1 | jq '.errors? | length')
  if [ "$ERROR_COUNT" -gt "0" ]; then
    echo "Upload failed"
    exit 1
  fi
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

set -e

if [ "$1" = "-h" ]; then
	usage
	exit
fi

ARTIFACTORY_USER=$(require_gradle_property "artifactoryUser") || exit $?
ARTIFACTORY_PASSWORD=$(require_gradle_property "artifactoryPassword") || exit $?
echo "Artifactory credentials retrieved successfully"

PROJECT=`ls -d *.xcodeproj`
TARGET=`basename $PROJECT .xcodeproj`

if [ "$TARGET" = "ALChiper" ]; then
	CORE_PRODUCT_NAME="libCipher"
	JSON_FILE="libALCipher.json"
else
	CORE_PRODUCT_NAME=$TARGET
	JSON_FILE="lib$TARGET.json"
fi

BUILD_DIR=$(xcodebuild -project $PROJECT -target $TARGET -showBuildSettings | grep -w BUILD_DIR | awk '{print $3}')
if [ -z $BUILD_DIR ]; then
	exit
fi

if [ "$1" = "-u" ]; then
	TYPE="universal"
	VARIANT="Release-$TYPE"
	PRODUCT="lib$TARGET.a.zip"
fi
if [ "$1" = "-s" ]; then
	TYPE="iphonesimulator"
	VARIANT="Release-$TYPE"
	PRODUCT="lib$TARGET.a.simul.zip"
fi
if [ "$1" = "-d" ]; then
	TYPE="iphoneos"
	VARIANT="Release-$TYPE"
	PRODUCT="lib$TARGET.a.device.zip"
fi

echo "== ========================================================== =="
echo "PROJECT: $PROJECT"
echo "TARGET: $TARGET"
echo "PRODUCT: $PRODUCT"
echo "CORE_PRODUCT_NAME: $CORE_PRODUCT_NAME"
echo -e "\n>> Preparing $PRODUCT in \n${BUILD_DIR}/${VARIANT}\n"
echo "== ========================================================== =="

cd "${BUILD_DIR}/${VARIANT}"
if [ -f $PRODUCT ]; then
	rm $PRODUCT
fi
zip -r $PRODUCT *

ARTIFACT_URL="https://artifactory-new.aliaslab.net/artifactory/SecureCallOTP_${CORE_PRODUCT_NAME}_iOS_Release/$TYPE"
ARTIFACT_MD5_CHECKSUM=$(md5 -q "$PRODUCT")
ARTIFACT_SHA1_CHECKSUM=$(shasum -a 1 "$PRODUCT" | awk '{ print $1 }')
JSON_URL=$ARTIFACT_URL/$JSON_FILE

echo "Downloading JSON from Artifactory"
ORIGINAL_INDEX_JSON=$(get_current_index_json "$ARTIFACTORY_USER" "$ARTIFACTORY_PASSWORD" "$JSON_URL") || exit $?
#echo $ORIGINAL_INDEX_JSON
ORIGINAL_VER=$(echo $ORIGINAL_INDEX_JSON | jq 'keys[-1]')
if [ -z $2 ]; then
	VER=$(increment_ver $ORIGINAL_VER)
else
	VER=$2
fi
echo "Updated version: $VER"

UPDATED_JSON=$(echo $ORIGINAL_INDEX_JSON | jq --arg "artifactURL" "$ARTIFACT_URL/$VER/$PRODUCT" '. + {"'$VER'": $artifactURL}') || exit $?
echo "Updated JSON is $UPDATED_JSON"

echo
echo "Uploading framework to Artifactory"
curl -u$ARTIFACTORY_USER:$ARTIFACTORY_PASSWORD --http1.1 -T $PRODUCT --header "X-Checksum-MD5:${ARTIFACT_MD5_CHECKSUM}" --header "X-Checksum-Sha1:${ARTIFACT_SHA1_CHECKSUM}" "$ARTIFACT_URL/$VER/$PRODUCT"

echo "Uploading JSON to Artifactory"
JSON_MD5_CHECKSUM=$(echo $UPDATED_JSON | md5 -q)
JSON_SHA1_CHECKSUM=$(echo $UPDATED_JSON | shasum -a 1 | awk '{ print $1 }')
echo $UPDATED_JSON | curl -u$ARTIFACTORY_USER:$ARTIFACTORY_PASSWORD --http1.1 -T - --header "X-Checksum-MD5:${JSON_MD5_CHECKSUM}" --header "X-Checksum-Sha1:${JSON_SHA1_CHECKSUM}" "$JSON_URL"

