#!/usr/bin/env bash

## Update the old http:// Artifactory addresses to the new server

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

##########################################################
## MAIN
##########################################################

if [ -z "$1" ]; then
  echo 'Missing configuration file path: specify one, e.g.: "IDSignMobile Standalone SDK/Artifactory/universal_artifactory.properties"'
  exit 1
fi
CONFIG_FILE_PATH=$1
echo Config file: ${CONFIG_FILE_PATH}

echo
echo "Select target:"
echo
select target in ios universal xcframework; do
	TARGET_TYPE=$target
	echo $TARGET_TYPE
	break
done

VERSION_STRING=""
JSON_TEMP_FILE="tm.json"

REPOSITORY_NAME=$(get_repository_name "${CONFIG_FILE_PATH}" $VERSION_STRING) || exit $?
echo "Repository name is $REPOSITORY_NAME"

ARTIFACTORY_URL=$(require_gradle_property "artifactoryURL") || exit $?
ARTIFACTORY_USER=$(require_gradle_property "artifactoryUser") || exit $?
ARTIFACTORY_PASSWORD=$(require_gradle_property "artifactoryPassword") || exit $?

FRAMEWORK_NAME=$(require_property "$CONFIG_FILE_PATH" "frameworkName") || exit $?

JSON_URL=$ARTIFACTORY_URL/$REPOSITORY_NAME/$TARGET_TYPE/$FRAMEWORK_NAME.json
echo "Downloading $JSON_URL..."

# download JSON
#curl -u$ARTIFACTORY_USER:$ARTIFACTORY_PASSWORD -w "\n$SEPARATOR%{http_code}\n" $JSON_URL  > $JSON
ORIGINAL_INDEX_JSON=$(get_current_index_json "$ARTIFACTORY_USER" "$ARTIFACTORY_PASSWORD" "$JSON_URL") || exit $?
echo ${ORIGINAL_INDEX_JSON} > $JSON_TEMP_FILE

# update JSON
sed -i -e 's/http:/https:/g' ${JSON_TEMP_FILE}
sed -i -e 's/artifactory-int.aliaslab.net:9082/artifactory-new.aliaslab.net/g' ${JSON_TEMP_FILE}
sed -i -e 's/artifactory-int.aliaslab.net:8082/artifactory-new.aliaslab.net/g' ${JSON_TEMP_FILE}

# upload JSON
JSON_MD5_CHECKSUM=$(cat $JSON_TEMP_FILE | md5 -q)
JSON_SHA1_CHECKSUM=$(cat $JSON_TEMP_FILE | shasum -a 1 | awk '{ print $1 }')
echo Sendig with: \"curl -T - --header "X-Checksum-MD5:${JSON_MD5_CHECKSUM}" --header "X-Checksum-Sha1:${JSON_SHA1_CHECKSUM}" ${JSON_URL}\"
CURL_OUTPUT=$(cat ${JSON_TEMP_FILE} | curl -u$ARTIFACTORY_USER:$ARTIFACTORY_PASSWORD -T - --header "X-Checksum-MD5:${JSON_MD5_CHECKSUM}" --header "X-Checksum-Sha1:${JSON_SHA1_CHECKSUM}" "$JSON_URL")
check_artifactory_response "$CURL_OUTPUT"

rm $JSON_TEMP_FILE
