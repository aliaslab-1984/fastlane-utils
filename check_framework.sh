#!/usr/bin/env bash

# written by Enrico Bonaldo

echo
if [ -z "$1" ]; then
	echo "Indicare un framework"
	echo -e "\tes. $0 SmartOTPSDK-Universal.framework/SmartOTPSDK \n"
	exit
fi

echo -e "File size:\t  $(ls -lh "$1" | awk '{print $5}')"
echo -e "Last modified on: $(date -r "$1")\n"
#lipo -info $1
ARCHITECTURES=$(lipo -archs "$1")
echo -e "Architectures:\t  $ARCHITECTURES"
echo

for ARCH in $ARCHITECTURES
do
	otool -l -arch $ARCH "$1" | grep -q LLVM
	if [ $? -eq 0 ]; then
		echo -e "\t[*] $ARCH has BITCODE"
	else
		echo -e "\t[X] $ARCH has not BITCODE"
	fi
done
echo

FW_PATH="$(cd "$(dirname "$1")"; pwd -P)/$(basename "$1")"
FW_PATH=$(dirname "$FW_PATH")
PLIST="$FW_PATH/Info.plist"
echo " plist: $PLIST"
if [ -f "$PLIST" ]; then
	VER=$(defaults read "$PLIST" CFBundleShortVersionString)
	BUILD=$(defaults read "$PLIST" CFBundleVersion)
	MIN_OS=$(defaults read "$PLIST" MinimumOSVersion)

	echo "Version: $VER"
	echo "Build: $BUILD"
	echo "Min OS: $MIN_OS"
	echo
fi
