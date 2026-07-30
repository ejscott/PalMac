#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
output_root="$project_root/outputs"
app_path="$output_root/PalMac.app"

cd "$project_root"
env \
  CLANG_MODULE_CACHE_PATH="$project_root/work/clang-cache" \
  SWIFTPM_CUSTOM_CACHE_PATH="$project_root/work/swiftpm-cache" \
  swift build -c release --disable-sandbox

mkdir -p "$output_root"
if [[ -e "$app_path" ]]; then
  backup_root="$project_root/work/package-backups"
  mkdir -p "$backup_root"
  previous_path="$backup_root/PalMac.previous.$(date +%Y%m%d%H%M%S).app"
  mv "$app_path" "$previous_path"
fi

mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$project_root/.build/release/PalMacApp" "$app_path/Contents/MacOS/PalMac"
cp "$project_root/.build/release/palmac" "$app_path/Contents/MacOS/PalMacHelper"
cp "$project_root/Packaging/Info.plist" "$app_path/Contents/Info.plist"
chmod 755 "$app_path/Contents/MacOS/PalMac" "$app_path/Contents/MacOS/PalMacHelper"
/usr/bin/xattr -cr "$app_path"
/usr/bin/codesign --force --deep --sign - "$app_path"
/usr/bin/codesign --verify --deep --strict "$app_path"

print "$app_path"
