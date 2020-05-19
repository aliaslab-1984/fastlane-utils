
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

SIMULATOR_LIBRARY_PATH="${BUILD_DIR}/${CONFIGURATION}-iphonesimulator/${FRAMEWORK_NAME}"
DEVICE_LIBRARY_PATH="${BUILD_DIR}/${CONFIGURATION}-iphoneos/${FRAMEWORK_NAME}"

FRAMEWORK_POSTFIX=".xcarchive/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework"

OUTPUT_DIR="${PROJECT_DIR}/Output/${FRAMEWORK_NAME}-${CONFIGURATION}/"
OUTPUT_FRAMEWORK="${OUTPUT_DIR}/${FRAMEWORK_NAME}.xcframework"

if [ -d "${OUTPUT_FRAMEWORK}" ]; then
  rm -rd "${OUTPUT_FRAMEWORK}"
fi

# Creates ${SIMULATOR_LIBRARY_PATH}.xcarchive
xcodebuild archive -scheme "${SCHEME}" -sdk iphoneos -archivePath "${SIMULATOR_LIBRARY_PATH}" SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES || exit $?

# Creates ${DEVICE_LIBRARY_PATH}.xcarchive
xcodebuild archive -scheme "${SCHEME}" -sdk iphonesimulator -archivePath "${DEVICE_LIBRARY_PATH}" SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES || exit $? 

# Creates the XCFramework
xcodebuild -create-xcframework -framework "${SIMULATOR_LIBRARY_PATH}${FRAMEWORK_POSTFIX}" -framework "${DEVICE_LIBRARY_PATH}${FRAMEWORK_POSTFIX}" -output "${OUTPUT_FRAMEWORK}"
