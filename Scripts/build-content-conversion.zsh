#!/bin/zsh
set -euo pipefail
setopt NULL_GLOB

function usage {
  cat <<'EOF'
Build a Mac-targeted PalMac package from a prepared legacy asset tree.

Usage:
  build-content-conversion.zsh \
    --source-root /path/to/LegacySource \
    [--overlay-root /path/to/MacCookedOverlay ...] \
    --package-name ExampleModelMac \
    --mod-name "Example Model Replacement (Mac)" \
    --output-root /path/to/Build \
    [--version 1.0.0] \
    [--author "Mod Author"] \
    [--description "Description"] \
    [--min-revision 100933] \
    [--unreal-pak /path/to/UnrealPak] \
    [--retoc /path/to/retoc] \
    [--plan-only]

Input roots must contain cooked files beneath Pal/Content. Later Mac overlay
roots replace files with the same relative path from the legacy source.

This tool does not extract archives, download tools, or grant permission to
redistribute another author's work.
EOF
}

source_root=""
overlay_roots=()
package_name=""
mod_name=""
output_root=""
mod_version="1.0.0"
author=""
description=""
min_revision=""
unreal_pak="${UNREAL_PAK:-}"
retoc_cmd="${RETOC:-${commands[retoc]:-}}"
plan_only=false

while (( $# > 0 )); do
  case "$1" in
    --source-root)
      source_root="${2:-}"
      shift 2
      ;;
    --overlay-root)
      overlay_roots+=("${2:-}")
      shift 2
      ;;
    --package-name)
      package_name="${2:-}"
      shift 2
      ;;
    --mod-name)
      mod_name="${2:-}"
      shift 2
      ;;
    --output-root)
      output_root="${2:-}"
      shift 2
      ;;
    --version)
      mod_version="${2:-}"
      shift 2
      ;;
    --author)
      author="${2:-}"
      shift 2
      ;;
    --description)
      description="${2:-}"
      shift 2
      ;;
    --min-revision)
      min_revision="${2:-}"
      shift 2
      ;;
    --unreal-pak)
      unreal_pak="${2:-}"
      shift 2
      ;;
    --retoc)
      retoc_cmd="${2:-}"
      shift 2
      ;;
    --plan-only)
      plan_only=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      print -u2 "Unknown argument: $1"
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$source_root" || -z "$package_name" || -z "$mod_name" || -z "$output_root" ]]; then
  print -u2 "Missing a required argument."
  usage >&2
  exit 2
fi

if [[ ! "$package_name" =~ '^[A-Za-z0-9_]{1,64}$' ]]; then
  print -u2 "Package name must contain 1-64 ASCII letters, numbers, or underscores."
  exit 2
fi

if (( ${#mod_name} == 0 || ${#mod_name} > 128 )); then
  print -u2 "Mod name must contain 1-128 characters."
  exit 2
fi

if (( ${#mod_version} == 0 || ${#mod_version} > 64 )); then
  print -u2 "Version must contain 1-64 characters."
  exit 2
fi

if [[ -n "$min_revision" && ! "$min_revision" =~ '^[0-9]+$' ]]; then
  print -u2 "Minimum revision must be a non-negative integer."
  exit 2
fi

source_root="${source_root:A}"
output_root="${output_root:A}"
resolved_overlays=()
for overlay_root in "${overlay_roots[@]}"; do
  resolved_overlays+=("${overlay_root:A}")
done
overlay_roots=("${resolved_overlays[@]}")

if [[ ! -d "$source_root" ]]; then
  print -u2 "Source root is not a directory: $source_root"
  exit 2
fi

for overlay_root in "${overlay_roots[@]}"; do
  if [[ ! -d "$overlay_root" ]]; then
    print -u2 "Overlay root is not a directory: $overlay_root"
    exit 2
  fi
done

allowed_extensions=(uasset uexp ubulk uptnl umap locres)

function validate_root {
  local root="$1"
  local label="$2"
  local path relative extension
  local count=0

  if [[ -n "$(/usr/bin/find "$root" -type l -print -quit)" ]]; then
    print -u2 "$label contains a symbolic link. Conversion inputs must contain regular files only."
    return 1
  fi

  while IFS= read -r -d '' path; do
    relative="${path#$root/}"
    if [[ "$relative" != Pal/Content/* ]]; then
      print -u2 "$label contains a file outside Pal/Content: $relative"
      return 1
    fi
    if [[ "$relative" == *[$'\r\n\"']* ]]; then
      print -u2 "$label contains a filename that cannot be represented safely: $relative"
      return 1
    fi
    extension="${relative:e:l}"
    if (( ${allowed_extensions[(Ie)$extension]} == 0 )); then
      print -u2 "$label contains an unsupported cooked file: $relative"
      return 1
    fi
    (( count += 1 ))
  done < <(/usr/bin/find "$root" -type f -print0)

  if (( count == 0 )); then
    print -u2 "$label contains no supported cooked Unreal files."
    return 1
  fi

  print -r -- "$count"
}

source_count="$(validate_root "$source_root" "Source root")"
overlay_count=0
for overlay_root in "${overlay_roots[@]}"; do
  current_count="$(validate_root "$overlay_root" "Mac overlay root")"
  (( overlay_count += current_count ))
done

typeset -A source_paths
typeset -A overlay_paths
while IFS= read -r -d '' path; do
  source_paths["${path#$source_root/}"]=1
done < <(/usr/bin/find "$source_root" -type f -print0)

for overlay_root in "${overlay_roots[@]}"; do
  while IFS= read -r -d '' path; do
    overlay_paths["${path#$overlay_root/}"]=1
  done < <(/usr/bin/find "$overlay_root" -type f -print0)
done

override_count=0
for relative in ${(k)overlay_paths}; do
  if [[ -n "${source_paths[$relative]:-}" ]]; then
    (( override_count += 1 ))
  fi
done

print "Conversion plan"
print "  Package: $package_name"
print "  Source: $source_root"
print "  Inputs: $source_count source file(s), $overlay_count Mac overlay file(s)"
print "  Overrides: $override_count source file(s) replaced by Mac-cooked data"
print "  Output: $output_root/$package_name"

if (( overlay_count == 0 )); then
  print "  Warning: no Mac-cooked overlay was supplied."
  print "  Container conversion alone does not convert textures, materials, or shaders."
fi

if $plan_only; then
  print "Plan only. No files were created and no external tools were run."
  exit 0
fi

if [[ -z "$unreal_pak" ]]; then
  default_engine_root="${UE_ROOT:-/Users/Shared/Epic Games/UE_5.1}"
  unreal_pak="$default_engine_root/Engine/Binaries/Mac/UnrealPak"
fi

if [[ ! -x "$unreal_pak" ]]; then
  print -u2 "UnrealPak was not found. Set UNREAL_PAK or pass --unreal-pak."
  exit 2
fi

if [[ -z "$retoc_cmd" || ! -x "$retoc_cmd" ]]; then
  print -u2 "Retoc was not found. Set RETOC, put retoc on PATH, or pass --retoc."
  exit 2
fi

/bin/mkdir -p "$output_root"
temporary_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/PalMacConversion.XXXXXX")"
function cleanup {
  /bin/rm -rf "$temporary_root"
}
trap cleanup EXIT INT TERM

stage_root="$temporary_root/Stage"
/bin/mkdir -p "$stage_root"
/usr/bin/ditto "$source_root" "$stage_root"
for overlay_root in "${overlay_roots[@]}"; do
  /usr/bin/ditto "$overlay_root" "$stage_root"
done

response_file="$temporary_root/$package_name.response"
: > "$response_file"
while IFS= read -r -d '' staged_file; do
  relative="${staged_file#$stage_root/}"
  print -r -- "\"$staged_file\" \"../../../$relative\"" >> "$response_file"
done < <(/usr/bin/find "$stage_root" -type f -print0)

legacy_pak="$temporary_root/${package_name}_Legacy.pak"
"$unreal_pak" "$legacy_pak" -Create="$response_file" -compress

package_root="$output_root/$package_name"
paks_root="$package_root/Paks"
/bin/mkdir -p "$paks_root"
container_base="${package_name}_P"
/bin/rm -f "$paks_root/$container_base.pak" \
  "$paks_root/$container_base.ucas" \
  "$paks_root/$container_base.utoc"

"$retoc_cmd" to-zen --version UE5_1 \
  "$legacy_pak" "$paks_root/$container_base.utoc"
"$retoc_cmd" verify "$paks_root/$container_base.utoc"
"$retoc_cmd" list --path "$paks_root/$container_base.utoc"

for required_file in \
  "$paks_root/$container_base.pak" \
  "$paks_root/$container_base.ucas" \
  "$paks_root/$container_base.utoc"; do
  if [[ ! -s "$required_file" ]]; then
    print -u2 "Expected IoStore file was not produced: $required_file"
    exit 4
  fi
done

info_file="$package_root/Info.json"
/usr/bin/plutil -create xml1 "$info_file"
/usr/bin/plutil -insert ModName -string "$mod_name" "$info_file"
/usr/bin/plutil -insert PackageName -string "$package_name" "$info_file"
/usr/bin/plutil -insert Version -string "$mod_version" "$info_file"
if [[ -n "$author" ]]; then
  /usr/bin/plutil -insert Author -string "$author" "$info_file"
fi
if [[ -n "$description" ]]; then
  /usr/bin/plutil -insert Description -string "$description" "$info_file"
fi
if [[ -n "$min_revision" ]]; then
  /usr/bin/plutil -insert MinRevision -integer "$min_revision" "$info_file"
fi
/usr/bin/plutil -insert InstallRule -json '[{"Type":"Paks","Targets":["./Paks"]}]' "$info_file"
/usr/bin/plutil -convert json "$info_file"

archive="$output_root/$package_name.zip"
/bin/rm -f "$archive" "$archive.sha256"
/usr/bin/ditto -c -k --keepParent "$package_root" "$archive"
(
  cd "$output_root"
  /usr/bin/shasum -a 256 "${archive:t}" > "${archive:t}.sha256"
)

repository_root="${0:A:h:h}"
if [[ -x "$repository_root/.build/release/palmac" ]]; then
  "$repository_root/.build/release/palmac" validate "$package_root"
else
  print "PalMac release binary was not found. Validate before installation:"
  print "  swift run palmac validate \"$package_root\""
fi

print "Created package: $package_root"
print "Created archive: $archive"
print "Created checksum: $archive.sha256"
