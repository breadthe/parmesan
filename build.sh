#!/bin/bash
# chmod +x ./build.sh

# run these only on 1st install, before anything else
# sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
# sudo xcodebuild -license accept
# xcodebuild -runFirstLaunch

# if not installed
# brew install xcodegen

# optional: SIGN_IDENTITY="Apple Development: you@example.com" ./build.sh
# keeps Full Disk Access across rebuilds (see README → Full Disk Access)

set -e
SIGN_ARGS=()
if [ -n "$SIGN_IDENTITY" ]; then
  SIGN_ARGS=(CODE_SIGN_IDENTITY="$SIGN_IDENTITY")
fi

xcodegen generate
xcodebuild -scheme Parmesan -configuration Release -derivedDataPath build "${SIGN_ARGS[@]}" build

# install
ditto build/Build/Products/Release/Parmesan.app /Applications/Parmesan.app
