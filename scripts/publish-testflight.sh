#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="ios/Outbound/Outbound.xcodeproj"
PROJECT_FILE="${PROJECT_PATH}/project.pbxproj"
SCHEME="Outbound"
APP_BUNDLE_ID="plainstride.outbound"
EXTENSION_BUNDLE_ID="${APP_BUNDLE_ID}.liveactivity"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-WT54K7D7VH}"
RELEASE_DOC="docs/testflight-1.0.md"

dry_run=false
commit_changes=true
requested_build=""

timestamp() {
  date '+%H:%M:%S'
}

log() {
  printf '[%s] %s\n' "$(timestamp)" "$*"
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

trap 'printf "error: failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

usage() {
  cat <<USAGE
Usage: $0 [--dry-run] [--no-commit] [--build-number NUMBER]

Increment Plainstride's build number, compile the Release configuration,
commit the verified metadata, create an App Store archive, and upload it to
App Store Connect for TestFlight processing.

Options:
  --dry-run              Print the planned version without changing anything.
  --no-commit            Do not commit the verified build-number changes.
  --build-number NUMBER  Use NUMBER instead of incrementing by one. NUMBER may
                         equal the current build to publish prepared metadata.
  -h, --help             Show this help.

Environment:
  DEVELOPMENT_TEAM  Apple Developer team. Defaults to WT54K7D7VH.
  ARCHIVE_PATH      Optional explicit .xcarchive path. The default is placed
                    in Xcode Organizer's standard Archives directory.
  ASC_KEY_PATH      Optional App Store Connect API private-key (.p8) path.
  ASC_KEY_ID        Key ID paired with ASC_KEY_PATH.
  ASC_ISSUER_ID     Issuer ID paired with ASC_KEY_PATH.

The upload is eligible for external TestFlight testing. App Store Connect may
still require processing, test notes, group assignment, or Beta App Review.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=true
      ;;
    --no-commit)
      commit_changes=false
      ;;
    --build-number)
      shift
      [[ $# -gt 0 ]] || fail "--build-number requires a value"
      requested_build="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
  shift
done

cd "$ROOT_DIR"

for tool in git ruby xcodebuild plutil; do
  command -v "$tool" >/dev/null 2>&1 || fail "required tool not found: $tool"
done

default_asc_key_path="${HOME}/Library/Application Support/Plainstride/AppStoreConnect/AuthKey_8F64X54A9C.p8"
default_asc_key_id="8F64X54A9C"
default_asc_issuer_id="fe8791ac-9cbb-424a-8491-233753db92a7"
if [[ -f "$default_asc_key_path" ]]; then
  asc_key_path="${ASC_KEY_PATH:-$default_asc_key_path}"
  asc_key_id="${ASC_KEY_ID:-$default_asc_key_id}"
  asc_issuer_id="${ASC_ISSUER_ID:-$default_asc_issuer_id}"
else
  asc_key_path="${ASC_KEY_PATH:-}"
  asc_key_id="${ASC_KEY_ID:-}"
  asc_issuer_id="${ASC_ISSUER_ID:-}"
fi
authentication_args=()
use_asc_api_key=false

if [[ -n "$asc_key_path" || -n "$asc_key_id" || -n "$asc_issuer_id" ]]; then
  [[ -n "$asc_key_path" && -n "$asc_key_id" && -n "$asc_issuer_id" ]] || \
    fail "ASC_KEY_PATH, ASC_KEY_ID, and ASC_ISSUER_ID must be set together"
  [[ -f "$asc_key_path" && -r "$asc_key_path" ]] || \
    fail "App Store Connect API key is not a readable file: $asc_key_path"
  authentication_args=(
    -authenticationKeyPath "$asc_key_path"
    -authenticationKeyID "$asc_key_id"
    -authenticationKeyIssuerID "$asc_issuer_id"
  )
  use_asc_api_key=true
fi

[[ -f "$PROJECT_FILE" ]] || fail "Xcode project file not found: $PROJECT_FILE"
[[ -f "$RELEASE_DOC" ]] || fail "release document not found: $RELEASE_DOC"

if [[ "$dry_run" == false && -n "$(git status --porcelain --untracked-files=no)" ]]; then
  fail "tracked files are already modified; commit or stash them before publishing"
elif [[ "$dry_run" == true && -n "$(git status --porcelain --untracked-files=no)" ]]; then
  log "Warning: tracked files are modified; a real publish would stop"
fi

version_info="$({ PROJECT_FILE="$PROJECT_FILE" APP_BUNDLE_ID="$APP_BUNDLE_ID" EXTENSION_BUNDLE_ID="$EXTENSION_BUNDLE_ID" ruby <<'RUBY'
path = ENV.fetch("PROJECT_FILE")
bundle_ids = [ENV.fetch("APP_BUNDLE_ID"), ENV.fetch("EXTENSION_BUNDLE_ID")]
lines = File.readlines(path)
builds = []
versions = []

lines.each_index do |start|
  next unless lines[start].include?("buildSettings = {")
  finish = (start + 1...lines.length).find { |index| lines[index].match?(/^\s*\};\s*$/) }
  next unless finish
  block = lines[start..finish].join
  next unless bundle_ids.any? { |bundle_id| block.include?("PRODUCT_BUNDLE_IDENTIFIER = #{bundle_id};") }

  build = block[/CURRENT_PROJECT_VERSION = ([^;]+);/, 1]
  version = block[/MARKETING_VERSION = ([^;]+);/, 1]
  abort "missing version settings in a release target block" unless build && version
  builds << build
  versions << version
end

abort "expected 4 app/extension build-setting blocks, found #{builds.length}" unless builds.length == 4
abort "app and extension build numbers differ: #{builds.uniq.join(', ')}" unless builds.uniq.length == 1
abort "app and extension marketing versions differ: #{versions.uniq.join(', ')}" unless versions.uniq.length == 1
puts "#{versions.first}\t#{builds.first}"
RUBY
  } 2>&1)" || fail "$version_info"

marketing_version="${version_info%%$'\t'*}"
current_build="${version_info#*$'\t'}"
[[ "$current_build" =~ ^[0-9]+$ ]] || fail "current build number is not an integer: $current_build"

if [[ -n "$requested_build" ]]; then
  [[ "$requested_build" =~ ^[0-9]+$ ]] || fail "requested build number must be an integer"
  next_build="$requested_build"
  (( next_build >= current_build )) || fail "new build number must not be lower than $current_build"
else
  next_build="$((current_build + 1))"
  (( next_build > current_build )) || fail "new build number must be greater than $current_build"
fi

if (( next_build == current_build )); then
  log "Plainstride ${marketing_version}: using prepared build ${current_build}"
else
  log "Plainstride ${marketing_version}: build ${current_build} -> ${next_build}"
fi
log "External TestFlight eligibility: enabled"

if [[ "$dry_run" == true ]]; then
  log "Dry run complete; no files changed"
  exit 0
fi

PROJECT_FILE="$PROJECT_FILE" APP_BUNDLE_ID="$APP_BUNDLE_ID" EXTENSION_BUNDLE_ID="$EXTENSION_BUNDLE_ID" OLD_BUILD="$current_build" NEW_BUILD="$next_build" ruby <<'RUBY'
path = ENV.fetch("PROJECT_FILE")
bundle_ids = [ENV.fetch("APP_BUNDLE_ID"), ENV.fetch("EXTENSION_BUNDLE_ID")]
old_build = ENV.fetch("OLD_BUILD")
new_build = ENV.fetch("NEW_BUILD")
lines = File.readlines(path)
updated = 0

lines.each_index do |start|
  next unless lines[start].include?("buildSettings = {")
  finish = (start + 1...lines.length).find { |index| lines[index].match?(/^\s*\};\s*$/) }
  next unless finish
  block = lines[start..finish].join
  next unless bundle_ids.any? { |bundle_id| block.include?("PRODUCT_BUNDLE_IDENTIFIER = #{bundle_id};") }

  index = (start..finish).find { |line_index| lines[line_index].include?("CURRENT_PROJECT_VERSION = #{old_build};") }
  abort "expected build #{old_build} in app/extension block" unless index
  lines[index] = lines[index].sub("CURRENT_PROJECT_VERSION = #{old_build};", "CURRENT_PROJECT_VERSION = #{new_build};")
  updated += 1
end

abort "expected to update 4 app/extension blocks, updated #{updated}" unless updated == 4
temporary_path = "#{path}.publish-tmp"
File.write(temporary_path, lines.join)
File.rename(temporary_path, path)
RUBY

OLD_BUILD="$current_build" NEW_BUILD="$next_build" MARKETING_VERSION="$marketing_version" RELEASE_DOC="$RELEASE_DOC" ruby <<'RUBY'
path = ENV.fetch("RELEASE_DOC")
old_build = ENV.fetch("OLD_BUILD")
new_build = ENV.fetch("NEW_BUILD")
marketing_version = ENV.fetch("MARKETING_VERSION")
text = File.read(path)
replacements = {
  "- Build: `#{old_build}`" => "- Build: `#{new_build}`",
  "Archive `#{marketing_version} (#{old_build})`" => "Archive `#{marketing_version} (#{new_build})`"
}
replacements.each do |before, after|
  abort "release document is missing: #{before}" unless text.include?(before)
  text = text.sub(before, after)
end
temporary_path = "#{path}.publish-tmp"
File.write(temporary_path, text)
File.rename(temporary_path, path)
RUBY

log "Running unsigned Release compile check..."
xcodebuild -quiet \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build

git diff --check

if [[ "$commit_changes" == true ]]; then
  git add "$PROJECT_FILE" "$RELEASE_DOC"
  if git diff --cached --quiet; then
    log "Build metadata is already committed"
  else
    git commit -m "Bump TestFlight build to ${next_build}"
    log "Committed verified build metadata"
  fi
else
  log "Leaving verified build metadata uncommitted (--no-commit)"
fi

archive_source_commit="$(git rev-parse HEAD)"

archive_date="$(date +%F)"
archive_stamp="$(date +%H.%M.%S)"
default_archive_dir="${HOME}/Library/Developer/Xcode/Archives/${archive_date}"
archive_path="${ARCHIVE_PATH:-${default_archive_dir}/Plainstride ${marketing_version} (${next_build}) ${archive_stamp}.xcarchive}"
[[ "$archive_path" == *.xcarchive ]] || fail "ARCHIVE_PATH must end in .xcarchive"
[[ ! -e "$archive_path" ]] || fail "archive path already exists: $archive_path"
mkdir -p "$(dirname "$archive_path")"

log "Creating signed App Store archive..."
log "Archive: $archive_path"
if [[ "$use_asc_api_key" == true ]]; then
  log "Using App Store Connect API key ${asc_key_id}"
else
  log "Using the Apple Account saved in Xcode"
fi
xcodebuild -quiet \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive_path" \
  -allowProvisioningUpdates \
  ${authentication_args[@]+"${authentication_args[@]}"} \
  archive

archived_version="$(plutil -extract ApplicationProperties.CFBundleShortVersionString raw -o - "$archive_path/Info.plist")"
archived_build="$(plutil -extract ApplicationProperties.CFBundleVersion raw -o - "$archive_path/Info.plist")"
[[ "$archived_version" == "$marketing_version" ]] || fail "archive version is $archived_version, expected $marketing_version"
[[ "$archived_build" == "$next_build" ]] || fail "archive build is $archived_build, expected $next_build"

if [[ "$commit_changes" == true && "$(git rev-parse HEAD)" != "$archive_source_commit" ]]; then
  fail "HEAD changed while archiving; archive preserved at $archive_path but upload stopped"
fi

export_options="$(mktemp /tmp/plainstride-testflight-export.XXXXXX)"
export_path="$(mktemp -d /tmp/plainstride-testflight-output.XXXXXX)"
trap 'rm -f "$export_options"' EXIT
cat >"$export_options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>upload</string>
  <key>method</key>
  <string>app-store-connect</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>${DEVELOPMENT_TEAM}</string>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
  <key>testFlightInternalTestingOnly</key>
  <false/>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
PLIST

log "Uploading build ${next_build} to App Store Connect..."
if ! xcodebuild \
  -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$export_options" \
  -allowProvisioningUpdates \
  ${authentication_args[@]+"${authentication_args[@]}"}; then
  printf '\nUpload failed, but the verified Organizer archive was preserved:\n  %s\n\n' "$archive_path" >&2
  printf 'Open Xcode > Window > Organizer, select Plainstride %s (%s), then choose Distribute App > App Store Connect.\n' "$marketing_version" "$next_build" >&2
  if [[ "$use_asc_api_key" == false ]]; then
    printf 'For reliable command-line uploads, set ASC_KEY_PATH, ASC_KEY_ID, and ASC_ISSUER_ID to an App Store Connect API key.\n' >&2
  fi
  exit 1
fi

log "Upload complete: Plainstride ${marketing_version} (${next_build})"
log "App Store Connect will process the build before external group assignment"
