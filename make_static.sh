#!/usr/bin/env bash

CONFIGURATION="Release"
TARGET="ALCipher-Universal"
PROJECT="ALChiper.xcodeproj"
BUILD_DIR=$(xcodebuild -project $PROJECT -target "$TARGET" -showBuildSettings | grep -w BUILD_DIR | cut -d= -f2)
BUILD_ROOT=$(xcodebuild -project $PROJECT -target "$TARGET" -showBuildSettings | grep -w BUILD_ROOT | cut -d= -f2)
PROJECT_NAME=$(xcodebuild -project $PROJECT -target "$TARGET" -showBuildSettings | grep -w PROJECT_NAME | awk '{print $3}')
echo "Building $PROJECT_NAME..."

# define output folder environment variable
UNIVERSAL_OUTPUTFOLDER=${BUILD_DIR}/${CONFIGURATION}-universal

# Step 1. Build Device and Simulator versions
# OTHER_CFLAGS="-fembed-bitcode" force BITCODE even in debug
xcodebuild OTHER_CFLAGS="-fembed-bitcode" -target ALChiper ONLY_ACTIVE_ARCH=NO -configuration ${CONFIGURATION} -sdk iphoneos BUILD_DIR="${BUILD_DIR}" BUILD_ROOT="${BUILD_ROOT}"
xcodebuild OTHER_CFLAGS="-fembed-bitcode" -target ALChiper -configuration ${CONFIGURATION} -sdk iphonesimulator BUILD_DIR="${BUILD_DIR}" BUILD_ROOT="${BUILD_ROOT}"

# make sure the output directory exists
mkdir -p "${UNIVERSAL_OUTPUTFOLDER}"

# Step 2. Create universal binary file using lipo
lipo -create -output "${UNIVERSAL_OUTPUTFOLDER}/lib${PROJECT_NAME}.a" "${BUILD_DIR}/${CONFIGURATION}-iphoneos/lib${PROJECT_NAME}.a" "${BUILD_DIR}/${CONFIGURATION}-iphonesimulator/lib${PROJECT_NAME}.a"

# Last touch. copy the header files. Just for convenience
cp -R "${BUILD_DIR}/${CONFIGURATION}-iphoneos/include" "${UNIVERSAL_OUTPUTFOLDER}/"

# Make a copy for the deploying script
mkdir build
cp -R "${UNIVERSAL_OUTPUTFOLDER}" build/

echo "------------------------------------------------"
STATIC_LIB="build/${CONFIGURATION}-universal/lib${PROJECT_NAME}.a"
#lipo -info "${STATIC_LIB}"
#otool -l "${STATIC_LIB}" | grep __LLVM > /dev/null

echo "Static library: ${STATIC_LIB}"
ARCHITECTURES=$(lipo -archs "${STATIC_LIB}")
echo -e "Architectures:\t  $ARCHITECTURES"
echo

for ARCH in $ARCHITECTURES
do
	otool -l -arch $ARCH "${STATIC_LIB}" | grep __LLVM > /dev/null
	if [ $? -eq 0 ]; then
		echo -e "\t[*] $ARCH has BITCODE"
	else
		echo -e "\t[X] $ARCH has not BITCODE"
	fi
done
echo "------------------------------------------------"

#open "${UNIVERSAL_OUTPUTFOLDER}/"