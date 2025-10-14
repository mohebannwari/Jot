#!/bin/bash

# Update Noty - Rebuild and reinstall the app
# Usage: ./update-noty.sh

set -e  # Exit on error

echo "🔨 Building Noty (Release)..."
xcodebuild -project Noty.xcodeproj -scheme Noty -configuration Release clean build > /dev/null 2>&1

echo "📦 Installing to /Applications..."
if [ -d "/Applications/Noty.app" ]; then
    # Quit the app if it's running
    osascript -e 'quit app "Noty"' 2>/dev/null || true
    sleep 0.5
    rm -rf "/Applications/Noty.app"
fi

cp -R ~/Library/Developer/Xcode/DerivedData/Noty-*/Build/Products/Release/Noty.app /Applications/

echo "🚀 Launching Noty..."
open -a /Applications/Noty.app

echo "✅ Noty updated successfully!"
