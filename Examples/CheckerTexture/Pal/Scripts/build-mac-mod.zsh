#!/bin/zsh
set -euo pipefail
setopt NULL_GLOB

project_dir="${0:A:h:h}"
example_root="${project_dir:h}"
repository_root="${example_root:h:h}"
project_file="$project_dir/Pal.uproject"
source_png="$example_root/SourceArt/PalMac_Checker.png"
build_root="$example_root/Build"
legacy_root="$build_root/Legacy"
import_root="$build_root/ImportSources"
package_root="$build_root/PalMacCheckerTexture"
response_file="$build_root/PalMacCheckerTexture.response"
engine_root="${UE_ROOT:-/Users/Shared/Epic Games/UE_5.1}"
editor_cmd="$engine_root/Engine/Binaries/Mac/UnrealEditor-Cmd"
unreal_pak="$engine_root/Engine/Binaries/Mac/UnrealPak"
retoc_cmd="${RETOC:-${commands[retoc]:-}}"
asset_root_relative="Pal/Model/Character/Player/Outfit/SK_Player_Female_Outfit_Cloth001"
asset_specs=(
  "v01:T_Player_Female_Outfit_Cloth001_v01_M01_B"
  "v01:T_Player_Female_Outfit_Cloth001_v01_M02_B"
  "v01:T_Player_Female_Outfit_Cloth001_v01_M03_B"
  "v02:T_Player_Female_Outfit_Cloth001_v02_M01_B"
  "v02:T_Player_Female_Outfit_Cloth001_v02_M02_B"
  "v03:T_Player_Female_Outfit_Cloth001_v03_M01_B"
  "v03:T_Player_Female_Outfit_Cloth001_v03_M02_B"
)

if [[ ! -x "$editor_cmd" || ! -x "$unreal_pak" ]]; then
  print -u2 "Unreal Engine 5.1 Mac tools were not found under: $engine_root"
  print -u2 "Set UE_ROOT to the full UE_5.1 installation path."
  exit 2
fi

if [[ -z "$retoc_cmd" || ! -x "$retoc_cmd" ]]; then
  print -u2 "Retoc was not found. Put retoc on PATH or set RETOC to its full path."
  print -u2 "Download it from: https://github.com/trumank/retoc/releases"
  exit 2
fi

mkdir -p "${source_png:h}" "$build_root" "$legacy_root"
if [[ ! -f "$source_png" ]]; then
  cache_root="$build_root/SwiftModuleCache"
  mkdir -p "$cache_root"
  env CLANG_MODULE_CACHE_PATH="$cache_root" SWIFT_MODULECACHE_PATH="$cache_root" \
    xcrun swift "$project_dir/Tools/generate_texture.swift" "$source_png"
fi

mkdir -p "$import_root"
for asset_spec in "${asset_specs[@]}"; do
  asset_name="${asset_spec#*:}"
  cp "$source_png" "$import_root/$asset_name.png"
done

print "Importing seven exact-path base-color textures..."
"$editor_cmd" "$project_file" \
  -run=pythonscript \
  -script="$project_dir/Scripts/create_checker_textures.py" \
  -unattended -nop4 -nosplash -NullRHI -NoSound

package_args=()
for asset_spec in "${asset_specs[@]}"; do
  asset_version="${asset_spec%%:*}"
  asset_name="${asset_spec#*:}"
  package_args+=("-Package=/Game/$asset_root_relative/$asset_version/$asset_name")
done

print "Cooking seven textures for macOS..."
"$editor_cmd" "$project_file" \
  -run=Cook -TargetPlatform=Mac \
  "${package_args[@]}" \
  -cooksinglepackagenorefs \
  -unversioned -compressed -unattended -nop4 -stdout

cooked_content="$project_dir/Saved/Cooked/Mac/Pal/Content"
asset_files=()
for asset_spec in "${asset_specs[@]}"; do
  asset_version="${asset_spec%%:*}"
  asset_name="${asset_spec#*:}"
  cooked_asset_dir="$cooked_content/$asset_root_relative/$asset_version"
  cooked_files=("$cooked_asset_dir/$asset_name".*)
  if (( ${#cooked_files} == 0 )); then
    print -u2 "No cooked texture files were produced for: $asset_name"
    exit 3
  fi
  asset_files+=("${cooked_files[@]}")
done

rm -f "$legacy_root/PalMacCheckerTexture_Legacy.pak"
: > "$response_file"
for asset_file in "${asset_files[@]}"; do
  relative_path="${asset_file#$cooked_content/}"
  print -r -- "\"$asset_file\" \"../../../Pal/Content/$relative_path\"" \
    >> "$response_file"
done

legacy_pak="$legacy_root/PalMacCheckerTexture_Legacy.pak"
"$unreal_pak" "$legacy_pak" -Create="$response_file" -compress

mkdir -p "$package_root/Paks"
rm -f "$package_root/Paks/PalMacCheckerTexture_P.pak" \
  "$package_root/Paks/PalMacCheckerTexture_P.ucas" \
  "$package_root/Paks/PalMacCheckerTexture_P.utoc"

print "Converting the Mac-cooked assets to UE5.1 IoStore..."
"$retoc_cmd" to-zen --version UE5_1 \
  "$legacy_pak" "$package_root/Paks/PalMacCheckerTexture_P.utoc"
"$retoc_cmd" verify "$package_root/Paks/PalMacCheckerTexture_P.utoc"
"$retoc_cmd" list --path "$package_root/Paks/PalMacCheckerTexture_P.utoc"

cp "$project_dir/PackageTemplate/Info.json" "$package_root/Info.json"

for required_file in \
  "$package_root/Paks/PalMacCheckerTexture_P.pak" \
  "$package_root/Paks/PalMacCheckerTexture_P.ucas" \
  "$package_root/Paks/PalMacCheckerTexture_P.utoc"; do
  if [[ ! -s "$required_file" ]]; then
    print -u2 "Expected IoStore file was not produced: $required_file"
    exit 4
  fi
done

archive="$build_root/PalMacCheckerTexture.zip"
rm -f "$archive" "$archive.sha256"
ditto -c -k --keepParent "$package_root" "$archive"
(
  cd "$build_root"
  shasum -a 256 "${archive:t}" > "${archive:t}.sha256"
)

if [[ -x "$repository_root/.build/release/palmac" ]]; then
  "$repository_root/.build/release/palmac" validate "$package_root"
else
  print "PalMac release binary not found; run this from the repository root:"
  print "  swift run palmac validate \"$package_root\""
fi

print "Created package: $package_root"
print "Created archive: $archive"
print "Created checksum: $archive.sha256"
