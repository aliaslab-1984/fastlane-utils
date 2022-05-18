
######################
# Options
######################

#SCHEME="${PROJECT_NAME}" # "IDSignMobile Standalone SDK"

while getopts ":f:" opt; do
  case $opt in
    f)
      SCHEME="${OPTARG}"
      ;;
    \?)
      echo "Invalid option: -${OPTARG}" >&2
      exit 1
      ;;
    :)
      echo "Option -${OPTARG} requires an argument." >&2
      exit 1
      ;;
  esac
done

if [ -z "$SCHEME" ]; then
  echo "Missing framework name: specify it with -f option"
  exit 1
fi

######################
# Main
######################

FRAMEWORK_NAME=$(echo $SCHEME | sed -e 's/ /_/g')

echo PWD: $PWD
echo BUILD_DIR: $BUILD_DIR
echo PROJECT_DIR: $PROJECT_DIR

if [ -z "$PROJECT_DIR" ]; then
      echo Started from CLI?
      PROJECT_DIR=$PWD
      CONFIGURATION="Release"
fi

BUILD_DIR="$PWD/Output"

SIMULATOR_LIBRARY_PATH="${BUILD_DIR}/${CONFIGURATION}-iphonesimulator/${FRAMEWORK_NAME}"
DEVICE_LIBRARY_PATH="${BUILD_DIR}/${CONFIGURATION}-iphoneos/${FRAMEWORK_NAME}"

FRAMEWORK_POSTFIX="/${FRAMEWORK_NAME}.framework"

OUTPUT_DIR="${PROJECT_DIR}/Output/${FRAMEWORK_NAME}-${CONFIGURATION}/"
OUTPUT_FRAMEWORK="${OUTPUT_DIR}${FRAMEWORK_NAME}.xcframework"

echo OUTPUT_DIR: $OUTPUT_DIR
echo OUTPUT_FRAMEWORK: $OUTPUT_FRAMEWORK
echo DEVICE_LIBRARY_PATH: $DEVICE_LIBRARY_PATH
echo SIMULATOR_LIBRARY_PATH: $SIMULATOR_LIBRARY_PATH

if [ -d "${OUTPUT_FRAMEWORK}" ]; then
  rm -rd "${OUTPUT_FRAMEWORK}"
fi

# Creates ${SIMULATOR_LIBRARY_PATH}.xcarchive
xcodebuild -scheme "${SCHEME}" -archivePath "${DEVICE_LIBRARY_PATH}" -sdk iphoneos CONFIGURATION_BUILD_DIR="${DEVICE_LIBRARY_PATH}" clean build || exit $? 
#SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES
#ENABLE_BITCODE=YES
#BITCODE_GENERATION_MODE=bitcode OTHER_C_FLAGS=-fembed-bitcode

# Creates ${DEVICE_LIBRARY_PATH}.xcarchive
xcodebuild -scheme "${SCHEME}" -archivePath "${SIMULATOR_LIBRARY_PATH}" -sdk iphonesimulator CONFIGURATION_BUILD_DIR="${SIMULATOR_LIBRARY_PATH}" clean build || exit $? 
#SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES
#ENABLE_BITCODE=YES
#BITCODE_GENERATION_MODE=bitcode OTHER_C_FLAGS=-fembed-bitcode

echo "===================================================="
echo "${SIMULATOR_LIBRARY_PATH}" 
echo "${SIMULATOR_LIBRARY_PATH}${FRAMEWORK_POSTFIX}" 
echo "${DEVICE_LIBRARY_PATH}"
echo "${DEVICE_LIBRARY_PATH}${FRAMEWORK_POSTFIX}"
echo "-> ${OUTPUT_FRAMEWORK}"

# Creates the XCFramework
xcodebuild -create-xcframework -framework "${SIMULATOR_LIBRARY_PATH}${FRAMEWORK_POSTFIX}" -framework "${DEVICE_LIBRARY_PATH}${FRAMEWORK_POSTFIX}" -output "${OUTPUT_FRAMEWORK}" || exit $? 

cd -
SHWD="${PWD}"
cd "${OUTPUT_FRAMEWORK}"
find . -name IDSignMobileSDK -print0|xargs -0 -n 1 "${SHWD}/check.sh"