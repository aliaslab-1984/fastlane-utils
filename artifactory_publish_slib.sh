#!/usr/bin/env bash

echo
echo "Archivia su Artifactory il risultato di un archive di ALCipher-Universal"
echo "Chiamare dalla cartella contenente ALChiper.xcodeproj"
echo -e "\n$0 -h for more info"
echo

usage() {
	echo
	echo "Usage: $0 -h|-u|-d|-s version"
	echo -e "\t-u \tupload universal static library"
	echo -e "\t-d \tupload device-only static library"
	echo -e "\t-s \tupload simulator-only static library"
	echo -e "\t-h \tthis help"
	echo
	echo "es. $0 -d 1.0.44"
	echo
}


require_ver() {
	if [ -z $1 ]; then
		echo "Indicare la versione"
		echo "    es. $0 -d 1.0.44"
		exit
	fi
}

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

# -----------------------------------------------------
# MAIN
# -----------------------------------------------------

if [ "$1" = "-h" ]; then
	usage
	exit
fi

require_ver $2
VER=$2

ARTIFACTORY_USER=$(require_gradle_property "artifactoryUser") || exit $?
ARTIFACTORY_PASSWORD=$(require_gradle_property "artifactoryPassword") || exit $?
echo "Artifactory credentials retrieved successfully"

BUILD_DIR=$(xcodebuild -project ALChiper.xcodeproj -target "ALCipher-Universal" -showBuildSettings | grep -w BUILD_DIR | awk '{print $3}')

if [ "$1" = "-u" ]; then
	TYPE="universal"
	VARIANT="Release-$TYPE"
	PRODUCT="libALChiper.a.zip"
fi
if [ "$1" = "-s" ]; then
	TYPE="iphonesimulator"
	VARIANT="Release-$TYPE"
	PRODUCT="libALChiper.a.simul.zip"
fi
if [ "$1" = "-d" ]; then
	TYPE="iphoneos"
	VARIANT="Release-$TYPE"
	PRODUCT="libALChiper.a.device.zip"
fi

echo -e "\n>> Preparing $PRODUCT in \n${BUILD_DIR}/${VARIANT}\n"

cd "${BUILD_DIR}/${VARIANT}"
if [ -f $PRODUCT ]; then
	rm $PRODUCT
fi
zip -r $PRODUCT *

echo "Uploading framework to Artifactory"
ARTIFACT_URL="https://artifactory-new.aliaslab.net/artifactory/SecureCallOTP_libCipher_iOS_Release/$TYPE"
ARTIFACT_MD5_CHECKSUM=$(md5 -q "$PRODUCT")
ARTIFACT_SHA1_CHECKSUM=$(shasum -a 1 "$PRODUCT" | awk '{ print $1 }')

JSON_URL=$ARTIFACT_URL/libALCipher.json

curl -u$ARTIFACTORY_USER:$ARTIFACTORY_PASSWORD -T $PRODUCT --header "X-Checksum-MD5:${ARTIFACT_MD5_CHECKSUM}" --header "X-Checksum-Sha1:${ARTIFACT_SHA1_CHECKSUM}" "$ARTIFACT_URL/$VER/$PRODUCT"

echo
ORIGINAL_INDEX_JSON=$(get_current_index_json "$ARTIFACTORY_USER" "$ARTIFACTORY_PASSWORD" "$JSON_URL") || exit $?
#echo $ORIGINAL_INDEX_JSON
UPDATED_JSON=$(echo $ORIGINAL_INDEX_JSON | jq --arg "artifactURL" "$ARTIFACT_URL/$VER/$PRODUCT" '. + {"'$VER'": $artifactURL}') || exit $?
echo "Updated JSON is $UPDATED_JSON"

echo "Uploading JSON to Artifactory"
JSON_MD5_CHECKSUM=$(echo $UPDATED_JSON | md5 -q)
JSON_SHA1_CHECKSUM=$(echo $UPDATED_JSON | shasum -a 1 | awk '{ print $1 }')
echo $UPDATED_JSON | curl -u$ARTIFACTORY_USER:$ARTIFACTORY_PASSWORD -T - --header "X-Checksum-MD5:${JSON_MD5_CHECKSUM}" --header "X-Checksum-Sha1:${JSON_SHA1_CHECKSUM}" "$JSON_URL"

