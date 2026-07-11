#!/bin/bash
set -e

echo "=== Creating Fake Xcode structure ==="
WORK_DIR="/tmp/sdk_setup"
# Clean up previous attempts
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "Extracting iPhoneOS18.1.sdk.zip..."
unzip -q /tmp/iPhoneOS18.1.sdk.zip

# Create the Xcode.app layout
FAKE_XCODE="$WORK_DIR/FakeXcode.app"
mkdir -p "$FAKE_XCODE/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs"
mkdir -p "$FAKE_XCODE/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator18.1.sdk/System/Library/Frameworks"
mkdir -p "$FAKE_XCODE/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator18.1.sdk/System/Library/PrivateFrameworks"
mkdir -p "$FAKE_XCODE/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX15.0.sdk/System/Library/Frameworks"
mkdir -p "$FAKE_XCODE/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX15.0.sdk/System/Library/PrivateFrameworks"

mkdir -p "$FAKE_XCODE/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift"
mkdir -p "$FAKE_XCODE/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift_static"
mkdir -p "$FAKE_XCODE/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/clang"

# Move the actual iPhoneOS SDK into place
mv "$WORK_DIR/iPhoneOS18.1.sdk" "$FAKE_XCODE/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS18.1.sdk"

# Make sure System/Library/Frameworks and PrivateFrameworks exist in the actual SDK
mkdir -p "$FAKE_XCODE/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS18.1.sdk/System/Library/Frameworks"
mkdir -p "$FAKE_XCODE/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS18.1.sdk/System/Library/PrivateFrameworks"

echo "Creating SDK version symlinks..."
# Create the standard platform.sdk symlinks pointing to the concrete version folders
cd "$FAKE_XCODE/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs"
ln -sf iPhoneOS18.1.sdk iPhoneOS.sdk

cd "$FAKE_XCODE/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs"
ln -sf iPhoneSimulator18.1.sdk iPhoneSimulator.sdk

cd "$FAKE_XCODE/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs"
ln -sf MacOSX15.0.sdk MacOSX.sdk

cd "$WORK_DIR"

echo "Setting up swift overlay folders..."
# Create the platform-specific subfolder 'iphoneos' in Toolchains Swift directories
mkdir -p "$FAKE_XCODE/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/iphoneos"
mkdir -p "$FAKE_XCODE/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift_static/iphoneos"

# Copy all files from the SDK's swift folder into the toolchain's platform swift directories
cp -r "$FAKE_XCODE/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS18.1.sdk/usr/lib/swift"/* \
      "$FAKE_XCODE/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/iphoneos/" 2>/dev/null || true

cp -r "$FAKE_XCODE/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS18.1.sdk/usr/lib/swift"/* \
      "$FAKE_XCODE/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift_static/iphoneos/" 2>/dev/null || true

echo "Installing SDK using xtool..."
xtool sdk install "$FAKE_XCODE"

echo "=== Verification ==="
xtool sdk status
swift sdk list
