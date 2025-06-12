#!/bin/bash
cd /Users/steveseguin/Code/vdon_flutter

# Clean any existing build artifacts
echo "Cleaning build directory..."
rm -rf build/

# Ensure proper Flutter path
export PATH="/Users/steveseguin/code/flutter/bin:$PATH"

# Clean Flutter cache
echo "Running Flutter clean..."
flutter clean

# Get dependencies
echo "Getting Flutter dependencies..."
flutter pub get

# Build iOS app
echo "Building iOS app..."
flutter build ios --release

echo "Build complete! You can now open Xcode and deploy to your device."