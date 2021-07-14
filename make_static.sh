#!/usr/bin/env bash

usage() {
	echo
	echo "Usage: $0 [-h|-d|-s|-u]"
	echo -e "\t-u \t\tbuild universal static library"
	echo -e "\t-d \t\tbuild device-only static library"
	echo -e "\t-s \t\tbuild simulator-only static library"
	echo -e "\t-h \t\tthis help"
	echo
}

partialInfo() {
	echo ">> built ${CONFIGURATION}-$1 in >>"
	echo "${BUILD_DIR}"
	echo
	lipo -info "${BUILD_DIR}/${CONFIGURATION}-$1/lib${PROJECT_NAME}.a"
	echo
}

bitInfo() {
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
}

if [ "$1" = "-h" ] || [ -z "$1" ]; then
	usage
	exit
fi

PROJECT=`ls -d *.xcodeproj`
TARGET=`basename $PROJECT .xcodeproj`

CONFIGURATION="Release"
BUILD_DIR=$(xcodebuild -project $PROJECT -target "$TARGET" -showBuildSettings | grep -w BUILD_DIR | awk '{print $3}')
BUILD_ROOT=$(xcodebuild -project $PROJECT -target "$TARGET" -showBuildSettings | grep -w BUILD_ROOT | awk '{print $3}')
PROJECT_NAME=$(xcodebuild -project $PROJECT -target "$TARGET" -showBuildSettings | grep -w PROJECT_NAME | awk '{print $3}')
echo "Building $PROJECT_NAME..."

# Step 1. Build Device and Simulator versions
# OTHER_CFLAGS="-fembed-bitcode" force BITCODE even in debug

if [ "$1" = "-d" ] || [ "$1" = "-u" ]; then
	xcodebuild clean build OTHER_CFLAGS="-fembed-bitcode" -target $TARGET ONLY_ACTIVE_ARCH=YES -configuration ${CONFIGURATION} -sdk iphoneos BUILD_DIR="${BUILD_DIR}" BUILD_ROOT="${BUILD_ROOT}"
fi
if [ "$1" = "-s" ]; then
	xcodebuild clean build OTHER_CFLAGS="-fembed-bitcode" -target $TARGET ONLY_ACTIVE_ARCH=NO -configuration ${CONFIGURATION} -sdk iphonesimulator BUILD_DIR="${BUILD_DIR}" BUILD_ROOT="${BUILD_ROOT}"
fi
if [ "$1" = "-u" ]; then
	xcodebuild clean build OTHER_CFLAGS="-fembed-bitcode" -target $TARGET ONLY_ACTIVE_ARCH=NO -arch i386 -arch x86_64 -configuration ${CONFIGURATION} -sdk iphonesimulator BUILD_DIR="${BUILD_DIR}" BUILD_ROOT="${BUILD_ROOT}"
fi

if [ "$1" = "-d" ]; then
	partialInfo "iphoneos"
	STATIC_LIB="${BUILD_DIR}/${CONFIGURATION}-iphoneos/lib${PROJECT_NAME}.a"
	bitInfo
	exit
fi
if [ "$1" = "-s" ]; then
	partialInfo "iphonesimulator"
	STATIC_LIB="${BUILD_DIR}/${CONFIGURATION}-iphonesimulator/lib${PROJECT_NAME}.a"
	bitInfo
	exit
fi

# define output folder environment variable
UNIVERSAL_OUTPUTFOLDER=${BUILD_DIR}/${CONFIGURATION}-universal

# make sure the output directory exists
mkdir -p "${UNIVERSAL_OUTPUTFOLDER}"

lipo -info "${BUILD_DIR}/${CONFIGURATION}-iphoneos/lib${PROJECT_NAME}.a"
lipo -info "${BUILD_DIR}/${CONFIGURATION}-iphonesimulator/lib${PROJECT_NAME}.a"

# Step 2. Create universal binary file using lipo
lipo -create -output "${UNIVERSAL_OUTPUTFOLDER}/lib${PROJECT_NAME}.a" "${BUILD_DIR}/${CONFIGURATION}-iphoneos/lib${PROJECT_NAME}.a" "${BUILD_DIR}/${CONFIGURATION}-iphonesimulator/lib${PROJECT_NAME}.a"

# Last touch. copy the header files. Just for convenience
cp -R "${BUILD_DIR}/${CONFIGURATION}-iphoneos/include" "${UNIVERSAL_OUTPUTFOLDER}/"

# Make a copy for the deploying script
mkdir build
cp -R "${UNIVERSAL_OUTPUTFOLDER}" build/

echo "------------------------------------------------"
STATIC_LIB="${UNIVERSAL_OUTPUTFOLDER}/lib${PROJECT_NAME}.a"
bitInfo

#open "${UNIVERSAL_OUTPUTFOLDER}/" 2> /dev/null