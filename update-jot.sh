#!/bin/bash

# Update Jot - Rebuild and reinstall the app
# Usage: ./update-jot.sh

set -e  # Exit on error

echo "🔨 Building Jot (Release)..."
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Release clean build > /dev/null 2>&1

echo "📦 Installing to /Applications..."
if [ -d "/Applications/Jot.app" ]; then
    # Quit the app if it's running
    osascript -e 'quit app "Jot"' 2>/dev/null || true
    sleep 0.5
    rm -rf "/Applications/Jot.app"
fi

cp -R ~/Library/Developer/Xcode/DerivedData/Jot-*/Build/Products/Release/Jot.app /Applications/

echo "🚀 Launching Jot..."
open -a /Applications/Jot.app

echo "✅ Jot updated successfully!"
