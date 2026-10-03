#!/bin/bash
# Build a notarized Developer ID disk image.
# The Team ID comes from COAMING_TEAM_ID. The notarization password stays in the
# login keychain under the profile named by COAMING_NOTARY_PROFILE (default
# coaming-notary). This script does not accept a password argument, and it
# refuses COAMING_CURSOR so the public image stays the default build.
set -euo pipefail

cd "$(dirname "$0")/.."

team="${COAMING_TEAM_ID:-}"
profile="${COAMING_NOTARY_PROFILE:-coaming-notary}"
app="build/export/Agent Coaming.app"

if [[ -z "$team" ]]; then
  echo "COAMING_TEAM_ID is not set."
  echo "Use the paid Apple Developer Program team. A Personal Team cannot notarize."
  exit 1
fi
if [[ ! "$team" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "COAMING_TEAM_ID must be 10 letters or digits."
  exit 1
fi
if [[ -n "${COAMING_CURSOR:-}" ]]; then
  echo "This command builds the public disk image and leaves Cursor out. Unset COAMING_CURSOR."
  exit 1
fi
if [[ ! "$profile" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "COAMING_NOTARY_PROFILE may contain only letters, digits, dots, underscores, and hyphens."
  exit 1
fi

echo "Checking the notarization keychain profile..."
if ! xcrun notarytool history --keychain-profile "$profile" >/dev/null; then
  echo "Keychain profile \"$profile\" is missing or was rejected."
  echo "Create it once. The password is prompted and stays in the login keychain:"
  echo "  xcrun notarytool store-credentials \"$profile\" --apple-id \"APPLE_ID_EMAIL\" --team-id \"$team\""
  exit 1
fi

identity="$(security find-identity -p codesigning -v | sed -n "s/.*\"\\(Developer ID Application: .* (${team})\\)\"/\\1/p")"
if [[ -z "$identity" ]]; then
  echo "No Developer ID Application certificate for this team."
  echo "Xcode → Settings → Accounts → the paid team → Manage Certificates → Developer ID Application."
  exit 1
fi
count="$(printf '%s\n' "$identity" | wc -l | tr -d ' ')"
if [[ "$count" != "1" ]]; then
  echo "Expected one Developer ID Application certificate for this team."
  exit 1
fi

env -u COAMING_CURSOR -u COAMING_CURSOR_CONDITION COAMING_TEAM_ID="$team" make generate

env -u COAMING_CURSOR -u COAMING_CURSOR_CONDITION xcodebuild \
  -project AgentCoaming.xcodeproj \
  -scheme CoamingHost \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath build/AgentCoaming.xcarchive \
  -allowProvisioningUpdates \
  archive

mkdir -p build
cat > build/ExportOptions.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>teamID</key>
  <string>${team}</string>
  <key>signingStyle</key>
  <string>automatic</string>
</dict>
</plist>
EOF

rm -rf build/export
env -u COAMING_CURSOR -u COAMING_CURSOR_CONDITION xcodebuild \
  -exportArchive \
  -archivePath build/AgentCoaming.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist build/ExportOptions.plist \
  -allowProvisioningUpdates

codesign --verify --deep --strict --verbose=2 "$app"
# -dvv prints one Authority line per certificate. Take the first without head(1):
# under pipefail, head closes the pipe early and the script stops before the product scan.
signature="$(codesign -dvv "$app" 2>&1 || true)"
signed_team="$(printf '%s\n' "$signature" | sed -n 's/^TeamIdentifier=//p')"
authority_lines="$(printf '%s\n' "$signature" | sed -n 's/^Authority=//p')"
authority="${authority_lines%%$'\n'*}"
if [[ "$signed_team" != "$team" ]]; then
  echo "Exported app team is ${signed_team:-missing}."
  exit 1
fi
if [[ "$authority" != Developer\ ID\ Application:* ]]; then
  echo "Exported app is not signed with Developer ID Application (${authority:-missing})."
  exit 1
fi

python3 scripts/check.py --app "$app"

version="$(defaults read "${PWD}/${app}/Contents/Info" CFBundleShortVersionString)"
if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
  echo "Unexpected app version: ${version}"
  exit 1
fi
dmg="build/AgentCoaming-${version}.dmg"

echo "Notarizing the app..."
ditto -c -k --keepParent "$app" build/AgentCoaming.zip
xcrun notarytool submit build/AgentCoaming.zip --keychain-profile "$profile" --wait
xcrun stapler staple "$app"

stage="build/dmg-root"
rm -rf "$stage"
mkdir -p "$stage"
ditto "$app" "${stage}/Agent Coaming.app"
ln -sfn /Applications "${stage}/Applications"
hdiutil detach "/Volumes/Agent Coaming" >/dev/null 2>&1 || true
hdiutil create -volname "Agent Coaming" -srcfolder "$stage" -ov -format UDZO "$dmg"

echo "Notarizing the disk image..."
codesign --sign "$identity" --timestamp "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
xcrun stapler staple "$dmg"
spctl --assess --type open --context context:primary-signature -v "$dmg"
echo "Disk image: ${dmg}"
