#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="ios/Outbound/Outbound.xcodeproj"
PROJECT_FILE="${PROJECT_PATH}/project.pbxproj"
SCHEME="Outbound"
APP_BUNDLE_ID="plainstride.outbound"
APP_APPLE_ID="6800191455"
EXTENSION_BUNDLE_ID="${APP_BUNDLE_ID}.liveactivity"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-WT54K7D7VH}"
RELEASE_DOC="docs/testflight-1.0.md"
ASC_API_BASE_URL="https://api.appstoreconnect.apple.com"
MAX_RELEASE_NOTE_ITEMS=5

dry_run=false
commit_changes=true
configure_beta=true
beta_setup_only=false
submit_public_release=false
manual_release=false
requested_version=""
requested_build=""
beta_group_name="${BETA_GROUP:-}"
beta_locale="${BETA_LOCALE:-en-US}"
app_store_locale="${APP_STORE_LOCALE:-en-US}"
asc_processing_timeout="${ASC_PROCESSING_TIMEOUT:-3600}"
asc_poll_interval="${ASC_POLL_INTERVAL:-30}"
asc_upload_timeout="${ASC_UPLOAD_TIMEOUT:-1800}"

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
Usage: $0 [--dry-run] [--no-commit] [--version VERSION]
          [--build-number NUMBER]
          [--beta-group NAME] [--setup-only | --skip-beta-setup]
          [--public-release [--manual-release]]

Increment Plainstride's build number, compile the Release configuration,
commit the verified metadata, create an App Store archive, and upload it to
App Store Connect. After processing, populate the build's release notes and
assign it to a TestFlight beta group. With --public-release, also attach the
build to its App Store version and submit it to App Review.

Options:
  --dry-run              Print the planned version without changing anything.
  --no-commit            Do not commit the verified version/build changes.
  --version VERSION      Use VERSION instead of the current marketing version.
                         Public releases otherwise bump its last component.
  --build-number NUMBER  Use NUMBER instead of incrementing by one. NUMBER may
                         equal the current build to publish prepared metadata.
  --beta-group NAME      Assign the build to this exact TestFlight group name.
                         If omitted, the sole internal group is selected.
  --setup-only           Configure an existing uploaded build without
                         compiling, archiving, or uploading it again.
  --beta-setup-only      Backward-compatible alias for --setup-only.
  --skip-beta-setup      Upload without release notes or group assignment.
                         Public-release setup still runs when requested.
  --public-release       Populate App Store What's New, attach the build to
                         the matching iOS version, and submit it to App Review.
                         The version releases automatically after approval.
  --manual-release       With --public-release, hold the approved version for
                         manual release in App Store Connect.
  -h, --help             Show this help.

Environment:
  DEVELOPMENT_TEAM  Apple Developer team. Defaults to WT54K7D7VH.
  ARCHIVE_PATH      Optional explicit .xcarchive path. The default is placed
                    in Xcode Organizer's standard Archives directory.
  ASC_KEY_PATH      Optional App Store Connect API private-key (.p8) path.
  ASC_KEY_ID        Key ID paired with ASC_KEY_PATH.
  ASC_ISSUER_ID     Issuer ID paired with ASC_KEY_PATH.
  BETA_GROUP        TestFlight group name; overridden by --beta-group.
  BETA_LOCALE       Release-notes locale. Defaults to en-US.
  APP_STORE_LOCALE  App Store What's New locale. Defaults to en-US.
  ASC_PROCESSING_TIMEOUT  Seconds to wait for processing. Defaults to 3600.
  ASC_POLL_INTERVAL      Poll interval in seconds. Defaults to 30.
  ASC_UPLOAD_TIMEOUT     Seconds to allow xcodebuild's upload/export phase.
                         Defaults to 1800; the archive is preserved on timeout.

Post-upload setup requires an App Store Connect API key. Public submission also
requires complete App Store metadata and an API key role allowed to submit it.
External groups may still require Beta App Review before testers receive it.
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
    --version)
      shift
      [[ $# -gt 0 ]] || fail "--version requires a value"
      requested_version="$1"
      ;;
    --build-number)
      shift
      [[ $# -gt 0 ]] || fail "--build-number requires a value"
      requested_build="$1"
      ;;
    --beta-group)
      shift
      [[ $# -gt 0 ]] || fail "--beta-group requires a value"
      beta_group_name="$1"
      ;;
    --setup-only|--beta-setup-only)
      beta_setup_only=true
      ;;
    --skip-beta-setup)
      configure_beta=false
      ;;
    --public-release)
      submit_public_release=true
      ;;
    --manual-release)
      manual_release=true
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

if [[ "$manual_release" == true && "$submit_public_release" == false ]]; then
  fail "--manual-release requires --public-release"
fi
if [[ "$beta_setup_only" == true && "$configure_beta" == false && "$submit_public_release" == false ]]; then
  fail "--setup-only requires beta setup or --public-release"
fi

cd "$ROOT_DIR"

for tool in curl find git jq pgrep ruby xcodebuild xcrun plutil; do
  command -v "$tool" >/dev/null 2>&1 || fail "required tool not found: $tool"
done

[[ "$asc_processing_timeout" =~ ^[1-9][0-9]*$ ]] || \
  fail "ASC_PROCESSING_TIMEOUT must be a positive integer"
[[ "$asc_poll_interval" =~ ^[1-9][0-9]*$ ]] || \
  fail "ASC_POLL_INTERVAL must be a positive integer"
[[ "$asc_upload_timeout" =~ ^[1-9][0-9]*$ ]] || \
  fail "ASC_UPLOAD_TIMEOUT must be a positive integer"
[[ "$APP_APPLE_ID" =~ ^[0-9]+$ ]] || \
  fail "APP_APPLE_ID must be the numeric App Store Connect Apple ID"
if [[ "$configure_beta" == true ]]; then
  [[ -n "$beta_locale" ]] || fail "BETA_LOCALE must not be empty"
fi
if [[ "$submit_public_release" == true ]]; then
  [[ -n "$app_store_locale" ]] || fail "APP_STORE_LOCALE must not be empty"
fi

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

if [[ "$dry_run" == false && ( "$configure_beta" == true || "$submit_public_release" == true ) && "$use_asc_api_key" == false ]]; then
  fail "post-upload setup requires ASC_KEY_PATH, ASC_KEY_ID, and ASC_ISSUER_ID (or the configured local key); omit --public-release and use --skip-beta-setup to upload only"
fi

[[ -f "$PROJECT_FILE" ]] || fail "Xcode project file not found: $PROJECT_FILE"
[[ -f "$RELEASE_DOC" ]] || fail "release document not found: $RELEASE_DOC"

documented_release_notes="$({ RELEASE_DOC="$RELEASE_DOC" ruby <<'RUBY'
path = ENV.fetch("RELEASE_DOC")
text = File.read(path, encoding: "UTF-8")
match = text.match(/^### Beta Release Notes\s*$\n(.*?)(?=^###?\s|\z)/m)
abort "release document is missing a Beta Release Notes section" unless match
notes = match[1].strip
abort "Beta Release Notes must not be empty" if notes.empty?
abort "Beta Release Notes exceed App Store Connect's 4,000-character limit" if notes.length > 4_000
puts notes
RUBY
  } 2>&1)" || fail "$documented_release_notes"

app_store_release_notes=""
if [[ "$submit_public_release" == true ]]; then
  app_store_release_notes="$({ RELEASE_DOC="$RELEASE_DOC" ruby <<'RUBY'
path = ENV.fetch("RELEASE_DOC")
text = File.read(path, encoding: "UTF-8")
match = text.match(/^### App Store What.s New\s*$\n(.*?)(?=^###?\s|\z)/m)
abort "release document is missing the App Store release-notes section" unless match
notes = match[1].strip
abort "App Store release notes must not be empty" if notes.empty?
abort "App Store release notes exceed the 4,000-character limit" if notes.length > 4_000
puts notes
RUBY
    } 2>&1)" || fail "$app_store_release_notes"
fi

if [[ "$dry_run" == false && "$beta_setup_only" == false && -n "$(git status --porcelain --untracked-files=no)" ]]; then
  fail "tracked files are already modified; commit or stash them before publishing"
elif [[ "$dry_run" == true && "$beta_setup_only" == false && -n "$(git status --porcelain --untracked-files=no)" ]]; then
  log "Warning: tracked files are modified; a real publish would stop"
fi

version_info="$({ PROJECT_FILE="$PROJECT_FILE" APP_BUNDLE_ID="$APP_BUNDLE_ID" EXTENSION_BUNDLE_ID="$EXTENSION_BUNDLE_ID" ruby <<'RUBY'
path = ENV.fetch("PROJECT_FILE")
bundle_ids = [ENV.fetch("APP_BUNDLE_ID"), ENV.fetch("EXTENSION_BUNDLE_ID")]
lines = File.readlines(path, encoding: "UTF-8")
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

current_marketing_version="${version_info%%$'\t'*}"
current_build="${version_info#*$'\t'}"
[[ "$current_build" =~ ^[0-9]+$ ]] || fail "current build number is not an integer: $current_build"

if [[ -n "$requested_version" ]]; then
  [[ "$requested_version" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || \
    fail "requested version must contain one to three dot-separated integers"
  marketing_version="$requested_version"
elif [[ "$submit_public_release" == true && "$beta_setup_only" == false ]]; then
  marketing_version="$({ CURRENT_VERSION="$current_marketing_version" ruby <<'RUBY'
version = ENV.fetch("CURRENT_VERSION")
parts = version.split(".")
abort "current marketing version must contain one to three dot-separated integers: #{version}" unless parts.length.between?(1, 3) && parts.all? { |part| part.match?(/\A\d+\z/) }
parts[-1] = (Integer(parts[-1], 10) + 1).to_s
puts parts.join(".")
RUBY
    } 2>&1)" || fail "$marketing_version"
else
  marketing_version="$current_marketing_version"
fi

if [[ "$submit_public_release" == true && "$marketing_version" != "$current_marketing_version" ]]; then
  app_store_release_notes="${app_store_release_notes//Plainstride ${current_marketing_version}/Plainstride ${marketing_version}}"
fi

if [[ "$beta_setup_only" == false ]]; then
  version_order="$({ CURRENT_VERSION="$current_marketing_version" NEXT_VERSION="$marketing_version" ruby <<'RUBY'
current = ENV.fetch("CURRENT_VERSION").split(".").map { |part| Integer(part, 10) }
requested = ENV.fetch("NEXT_VERSION").split(".").map { |part| Integer(part, 10) }
width = [current.length, requested.length].max
puts((requested.fill(0, requested.length...width) <=> current.fill(0, current.length...width)))
RUBY
    } 2>&1)" || fail "$version_order"
  (( version_order >= 0 )) || fail "new marketing version must not be lower than ${current_marketing_version}"
fi

if [[ -n "$requested_build" ]]; then
  [[ "$requested_build" =~ ^[0-9]+$ ]] || fail "requested build number must be an integer"
  next_build="$requested_build"
  if [[ "$beta_setup_only" == false ]]; then
    (( next_build >= current_build )) || fail "new build number must not be lower than $current_build"
  fi
elif [[ "$beta_setup_only" == true ]]; then
  next_build="$current_build"
else
  next_build="$((current_build + 1))"
  (( next_build > current_build )) || fail "new build number must be greater than $current_build"
fi

release_notes_generated=false
if [[ "$beta_setup_only" == true ]] || (( next_build == current_build )); then
  release_notes="$documented_release_notes"
else
  last_release_commit="$(git log \
    --extended-regexp \
    --grep='^(Bump TestFlight build to [0-9]+|Prepare Plainstride [0-9]+(\.[0-9]+){0,2} build [0-9]+)$' \
    --format='%H' \
    -1)"
  [[ -n "$last_release_commit" ]] || fail "could not find the previous TestFlight release commit"

  release_subjects="$(git log \
    --format='%s' \
    "${last_release_commit}..HEAD" \
    -- ios/Outbound backend Package.swift)"
  [[ -n "$release_subjects" ]] || \
    fail "no product commits found since the previous TestFlight release"

  release_notes="$({ RELEASE_SUBJECTS="$release_subjects" MAX_ITEMS="$MAX_RELEASE_NOTE_ITEMS" ruby <<'RUBY'
subjects = ENV.fetch("RELEASE_SUBJECTS").lines.map(&:strip).reject(&:empty?)
max_items = Integer(ENV.fetch("MAX_ITEMS"), 10)
abort "MAX_RELEASE_NOTE_ITEMS must be positive" unless max_items.positive?

visible = subjects.first(max_items).map do |subject|
  shortened = subject.length > 120 ? "#{subject[0, 117]}..." : subject
  "- #{shortened}"
end
remaining = subjects.length - visible.length
visible << "- Plus #{remaining} more fixes and improvements" if remaining.positive?
notes = visible.join("\n")
abort "generated Beta Release Notes exceed App Store Connect's 4,000-character limit" if notes.length > 4_000
puts notes
RUBY
    } 2>&1)" || fail "$release_notes"
  release_notes_generated=true
fi

if [[ "$beta_setup_only" == true ]]; then
  log "Plainstride ${marketing_version}: configuring existing build ${next_build}"
elif [[ "$marketing_version" == "$current_marketing_version" ]] && (( next_build == current_build )); then
  log "Plainstride ${marketing_version}: using prepared build ${current_build}"
else
  log "Plainstride ${current_marketing_version} (${current_build}) -> ${marketing_version} (${next_build})"
fi
log "External TestFlight eligibility: enabled"
if [[ "$configure_beta" == true ]]; then
  if [[ -n "$beta_group_name" ]]; then
    log "Beta setup: release notes (${beta_locale}) and group '${beta_group_name}'"
  else
    log "Beta setup: release notes (${beta_locale}) and the sole internal group"
  fi
else
  log "Beta setup: skipped"
fi
if [[ "$submit_public_release" == true ]]; then
  if [[ "$manual_release" == true ]]; then
    log "App Store submission: ${app_store_locale}, manual release after approval"
  else
    log "App Store submission: ${app_store_locale}, automatic release after approval"
  fi
else
  log "App Store submission: skipped"
fi
if [[ "$release_notes_generated" == true ]]; then
  log "Release notes from commits after $(git rev-parse --short "$last_release_commit"):"
  while IFS= read -r release_note_line; do
    log "  ${release_note_line}"
  done <<<"$release_notes"
else
  log "Release notes: using the saved notes for build ${next_build}"
fi

if [[ "$dry_run" == true ]]; then
  log "Dry run complete; no files changed"
  exit 0
fi

if [[ "$beta_setup_only" == false ]]; then
PROJECT_FILE="$PROJECT_FILE" APP_BUNDLE_ID="$APP_BUNDLE_ID" EXTENSION_BUNDLE_ID="$EXTENSION_BUNDLE_ID" OLD_VERSION="$current_marketing_version" NEW_VERSION="$marketing_version" OLD_BUILD="$current_build" NEW_BUILD="$next_build" ruby <<'RUBY'
path = ENV.fetch("PROJECT_FILE")
bundle_ids = [ENV.fetch("APP_BUNDLE_ID"), ENV.fetch("EXTENSION_BUNDLE_ID")]
old_version = ENV.fetch("OLD_VERSION")
new_version = ENV.fetch("NEW_VERSION")
old_build = ENV.fetch("OLD_BUILD")
new_build = ENV.fetch("NEW_BUILD")
lines = File.readlines(path, encoding: "UTF-8")
updated_builds = 0
updated_versions = 0

lines.each_index do |start|
  next unless lines[start].include?("buildSettings = {")
  finish = (start + 1...lines.length).find { |index| lines[index].match?(/^\s*\};\s*$/) }
  next unless finish
  block = lines[start..finish].join
  next unless bundle_ids.any? { |bundle_id| block.include?("PRODUCT_BUNDLE_IDENTIFIER = #{bundle_id};") }

  index = (start..finish).find { |line_index| lines[line_index].include?("CURRENT_PROJECT_VERSION = #{old_build};") }
  abort "expected build #{old_build} in app/extension block" unless index
  lines[index] = lines[index].sub("CURRENT_PROJECT_VERSION = #{old_build};", "CURRENT_PROJECT_VERSION = #{new_build};")
  updated_builds += 1

  index = (start..finish).find { |line_index| lines[line_index].include?("MARKETING_VERSION = #{old_version};") }
  abort "expected marketing version #{old_version} in app/extension block" unless index
  lines[index] = lines[index].sub("MARKETING_VERSION = #{old_version};", "MARKETING_VERSION = #{new_version};")
  updated_versions += 1
end

abort "expected to update 4 app/extension build numbers, updated #{updated_builds}" unless updated_builds == 4
abort "expected to update 4 app/extension marketing versions, updated #{updated_versions}" unless updated_versions == 4
temporary_path = "#{path}.publish-tmp"
File.write(temporary_path, lines.join)
File.rename(temporary_path, path)
RUBY

OLD_BUILD="$current_build" NEW_BUILD="$next_build" OLD_VERSION="$current_marketing_version" NEW_VERSION="$marketing_version" RELEASE_DOC="$RELEASE_DOC" RELEASE_NOTES="$release_notes" APP_STORE_RELEASE_NOTES="$app_store_release_notes" UPDATE_APP_STORE_NOTES="$submit_public_release" ruby <<'RUBY'
path = ENV.fetch("RELEASE_DOC")
old_build = ENV.fetch("OLD_BUILD")
new_build = ENV.fetch("NEW_BUILD")
old_version = ENV.fetch("OLD_VERSION")
new_version = ENV.fetch("NEW_VERSION")
release_notes = ENV.fetch("RELEASE_NOTES")
app_store_release_notes = ENV.fetch("APP_STORE_RELEASE_NOTES")
update_app_store_notes = ENV.fetch("UPDATE_APP_STORE_NOTES") == "true"
text = File.read(path, encoding: "UTF-8")
replacements = {
  "# TestFlight and App Store #{old_version} Submission Sheet" => "# TestFlight and App Store #{new_version} Submission Sheet",
  "- Version: `#{old_version}`" => "- Version: `#{new_version}`",
  "- Build: `#{old_build}`" => "- Build: `#{new_build}`",
  "Archive `#{old_version} (#{old_build})`" => "Archive `#{new_version} (#{new_build})`"
}
replacements.each do |before, after|
  abort "release document is missing: #{before}" unless text.include?(before)
  text = text.sub(before, after)
end
notes_pattern = /^### Beta Release Notes\s*$\n.*?(?=^###?\s|\z)/m
abort "release document is missing the Beta Release Notes section" unless text.match?(notes_pattern)
text = text.sub(notes_pattern, "### Beta Release Notes\n\n#{release_notes}\n\n")
if update_app_store_notes
  app_store_notes_pattern = /^### App Store What.s New\s*$\n.*?(?=^###?\s|\z)/m
  abort "release document is missing the App Store release-notes section" unless text.match?(app_store_notes_pattern)
  text = text.sub(app_store_notes_pattern, "### App Store What's New\n\n#{app_store_release_notes}\n\n")
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
    if [[ "$submit_public_release" == true || "$marketing_version" != "$current_marketing_version" ]]; then
      git commit -m "Prepare Plainstride ${marketing_version} build ${next_build}"
    else
      git commit -m "Bump TestFlight build to ${next_build}"
    fi
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
export_destination="upload"
if [[ "$use_asc_api_key" == true ]]; then
  export_destination="export"
fi
cat >"$export_options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>${export_destination}</string>
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

terminate_process_tree() {
  local process_id="$1"
  local signal="$2"
  local child_id

  while IFS= read -r child_id; do
    [[ -n "$child_id" ]] || continue
    terminate_process_tree "$child_id" "$signal"
  done < <(pgrep -P "$process_id" 2>/dev/null || true)

  kill "-$signal" "$process_id" 2>/dev/null || true
}

run_with_timeout() {
  local timeout_seconds="$1"
  local operation="$2"
  shift 2
  local process_id elapsed

  "$@" &
  process_id="$!"
  elapsed=0
  while kill -0 "$process_id" 2>/dev/null; do
    if (( elapsed >= timeout_seconds )); then
      log "${operation} exceeded ${timeout_seconds}s; stopping it and preserving the archive"
      terminate_process_tree "$process_id" TERM
      sleep 2
      terminate_process_tree "$process_id" KILL
      wait "$process_id" 2>/dev/null || true
      return 124
    fi
    sleep 1
    (( elapsed += 1 ))
  done

  wait "$process_id"
}

if [[ "$use_asc_api_key" == true ]]; then
  log "Exporting signed IPA for App Store Connect (timeout: ${asc_upload_timeout}s)..."
  export_status=0
  if run_with_timeout "$asc_upload_timeout" "IPA export" xcodebuild \
    -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_path" \
    -exportOptionsPlist "$export_options" \
    -allowProvisioningUpdates; then
    export_status=0
  else
    export_status=$?
  fi
  if (( export_status != 0 )); then
    if (( export_status == 124 )); then
      printf '\nIPA export timed out after %ss, but the verified Organizer archive was preserved:\n  %s\n\n' "$asc_upload_timeout" "$archive_path" >&2
    else
      printf '\nIPA export failed, but the verified Organizer archive was preserved:\n  %s\n\n' "$archive_path" >&2
    fi
    exit 1
  fi

  ipa_path="$(find "$export_path" -maxdepth 1 -type f -name '*.ipa' -print -quit)"
  [[ -n "$ipa_path" ]] || fail "Xcode export did not produce an IPA in $export_path"
  log "Uploading build ${next_build} with altool (timeout: ${asc_upload_timeout}s)..."
  upload_status=0
  if run_with_timeout "$asc_upload_timeout" "App Store Connect upload" xcrun altool \
    --upload-package "$ipa_path" \
    --platform ios \
    --apple-id "$APP_APPLE_ID" \
    --bundle-id "$APP_BUNDLE_ID" \
    --bundle-version "$next_build" \
    --bundle-short-version-string "$marketing_version" \
    --api-key "$asc_key_id" \
    --api-issuer "$asc_issuer_id" \
    --p8-file-path "$asc_key_path"; then
    upload_status=0
  else
    upload_status=$?
  fi
else
  log "Uploading build ${next_build} to App Store Connect (timeout: ${asc_upload_timeout}s)..."
  upload_status=0
  if run_with_timeout "$asc_upload_timeout" "Xcode export/upload" xcodebuild \
    -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_path" \
    -exportOptionsPlist "$export_options" \
    -allowProvisioningUpdates; then
    upload_status=0
  else
    upload_status=$?
  fi
fi
if (( upload_status != 0 )); then
  if (( upload_status == 124 )); then
    printf '\nUpload timed out after %ss, but the verified Organizer archive was preserved:\n  %s\n\n' "$asc_upload_timeout" "$archive_path" >&2
  else
    printf '\nUpload failed, but the verified Organizer archive was preserved:\n  %s\n\n' "$archive_path" >&2
  fi
  printf 'Open Xcode > Window > Organizer, select Plainstride %s (%s), then choose Distribute App > App Store Connect.\n' "$marketing_version" "$next_build" >&2
  if [[ "$use_asc_api_key" == false ]]; then
    printf 'For reliable command-line uploads, set ASC_KEY_PATH, ASC_KEY_ID, and ASC_ISSUER_ID to an App Store Connect API key.\n' >&2
  fi
  exit 1
fi

log "Upload complete: Plainstride ${marketing_version} (${next_build})"
else
  log "Skipping compile, archive, and upload for existing build ${next_build}"
fi

if [[ "$configure_beta" == false && "$submit_public_release" == false ]]; then
  log "Skipped App Store Connect post-upload setup"
  exit 0
fi

asc_token() {
  ASC_KEY_PATH="$asc_key_path" ASC_KEY_ID="$asc_key_id" ASC_ISSUER_ID="$asc_issuer_id" ruby <<'RUBY'
require "base64"
require "json"
require "openssl"

def base64url(value)
  Base64.urlsafe_encode64(value).delete("=")
end

now = Time.now.to_i
header = { alg: "ES256", kid: ENV.fetch("ASC_KEY_ID"), typ: "JWT" }
claims = {
  iss: ENV.fetch("ASC_ISSUER_ID"),
  iat: now,
  exp: now + 15 * 60,
  aud: "appstoreconnect-v1"
}
signing_input = "#{base64url(JSON.generate(header))}.#{base64url(JSON.generate(claims))}"
key = OpenSSL::PKey::EC.new(File.read(ENV.fetch("ASC_KEY_PATH")))
der_signature = key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(signing_input))
sequence = OpenSSL::ASN1.decode(der_signature)
raw_signature = sequence.value.map do |integer|
  hex = integer.value.to_i.to_s(16).rjust(64, "0")
  abort "unexpected App Store Connect signature size" if hex.length > 64
  [hex].pack("H*")
end.join
puts "#{signing_input}.#{base64url(raw_signature)}"
RUBY
}

asc_request() {
  local method="$1"
  local path="$2"
  local payload="${3:-}"
  local token response_path http_status error_summary
  token="$(asc_token)"
  response_path="$(mktemp /tmp/plainstride-asc-response.XXXXXX)"

  local -a curl_args=(
    --silent
    --show-error
    --request "$method"
    --header "Authorization: Bearer ${token}"
    --header "Accept: application/json"
    --output "$response_path"
    --write-out '%{http_code}'
  )
  if [[ -n "$payload" ]]; then
    curl_args+=(--header "Content-Type: application/json" --data "$payload")
  fi

  if ! http_status="$(curl "${curl_args[@]}" "${ASC_API_BASE_URL}${path}")"; then
    rm -f "$response_path"
    fail "App Store Connect API request failed: ${method} ${path}"
  fi

  if [[ "$http_status" =~ ^2[0-9][0-9]$ ]]; then
    cat "$response_path"
    rm -f "$response_path"
    return 0
  fi

  error_summary="$(jq -r '[.errors[]? | [.status, .code, .title, .detail] | map(select(. != null and . != "")) | join(" ")] | join("; ")' "$response_path" 2>/dev/null || true)"
  rm -f "$response_path"
  [[ -n "$error_summary" ]] || error_summary="HTTP ${http_status}"
  fail "App Store Connect API ${method} ${path}: ${error_summary}"
}

urlencode() {
  jq -rn --arg value "$1" '$value | @uri'
}

log "Waiting for App Store Connect to process build ${next_build}..."
encoded_bundle_id="$(urlencode "$APP_BUNDLE_ID")"
apps_json="$(asc_request GET "/v1/apps?filter%5BbundleId%5D=${encoded_bundle_id}&limit=2")"
app_count="$(jq '.data | length' <<<"$apps_json")"
(( app_count == 1 )) || fail "expected one App Store Connect app for ${APP_BUNDLE_ID}, found ${app_count}"
app_id="$(jq -r '.data[0].id' <<<"$apps_json")"

encoded_app_id="$(urlencode "$app_id")"
encoded_build="$(urlencode "$next_build")"
encoded_version="$(urlencode "$marketing_version")"
processing_started="$(date +%s)"
build_id=""

while true; do
  builds_json="$(asc_request GET "/v1/builds?filter%5Bapp%5D=${encoded_app_id}&filter%5Bversion%5D=${encoded_build}&filter%5BpreReleaseVersion.version%5D=${encoded_version}&sort=-uploadedDate&limit=2&fields%5Bbuilds%5D=version%2CprocessingState%2CuploadedDate")"
  build_count="$(jq '.data | length' <<<"$builds_json")"
  (( build_count <= 1 )) || fail "App Store Connect returned multiple ${marketing_version} (${next_build}) builds"

  if (( build_count == 1 )); then
    processing_state="$(jq -r '.data[0].attributes.processingState // empty' <<<"$builds_json")"
    case "$processing_state" in
      VALID)
        build_id="$(jq -r '.data[0].id' <<<"$builds_json")"
        break
        ;;
      FAILED|INVALID)
        fail "App Store Connect processing ended in ${processing_state} for build ${next_build}"
        ;;
      PROCESSING|"")
        ;;
      *)
        fail "unknown App Store Connect processing state: ${processing_state}"
        ;;
    esac
  fi

  processing_elapsed="$(( $(date +%s) - processing_started ))"
  (( processing_elapsed < asc_processing_timeout )) || \
    fail "timed out after ${asc_processing_timeout}s waiting for build ${next_build}; the upload remains in App Store Connect"
  log "Build ${next_build} is still processing (${processing_elapsed}s elapsed)"
  sleep "$asc_poll_interval"
done

log "Build ${next_build} processed successfully"
encoded_build_id="$(urlencode "$build_id")"

if [[ "$configure_beta" == true ]]; then
encoded_locale="$(urlencode "$beta_locale")"
localizations_json="$(asc_request GET "/v1/betaBuildLocalizations?filter%5Bbuild%5D=${encoded_build_id}&filter%5Blocale%5D=${encoded_locale}&limit=2")"
localization_count="$(jq '.data | length' <<<"$localizations_json")"
(( localization_count <= 1 )) || fail "multiple ${beta_locale} release-note records exist for build ${next_build}"

if (( localization_count == 0 )); then
  localization_payload="$(jq -cn \
    --arg locale "$beta_locale" \
    --arg whats_new "$release_notes" \
    --arg build_id "$build_id" \
    '{data:{type:"betaBuildLocalizations",attributes:{locale:$locale,whatsNew:$whats_new},relationships:{build:{data:{type:"builds",id:$build_id}}}}}')"
  asc_request POST "/v1/betaBuildLocalizations" "$localization_payload" >/dev/null
else
  localization_id="$(jq -r '.data[0].id' <<<"$localizations_json")"
  localization_payload="$(jq -cn \
    --arg id "$localization_id" \
    --arg whats_new "$release_notes" \
    '{data:{type:"betaBuildLocalizations",id:$id,attributes:{whatsNew:$whats_new}}}')"
  asc_request PATCH "/v1/betaBuildLocalizations/$(urlencode "$localization_id")" "$localization_payload" >/dev/null
fi
log "Published ${beta_locale} Beta Release Notes"

groups_json="$(asc_request GET "/v1/betaGroups?filter%5Bapp%5D=${encoded_app_id}&limit=200&fields%5BbetaGroups%5D=name%2CisInternalGroup")"
if [[ -n "$beta_group_name" ]]; then
  matching_groups="$(jq -c --arg name "$beta_group_name" '[.data[] | select(.attributes.name == $name)]' <<<"$groups_json")"
else
  matching_groups="$(jq -c '[.data[] | select(.attributes.isInternalGroup == true)]' <<<"$groups_json")"
fi
matching_group_count="$(jq 'length' <<<"$matching_groups")"

if (( matching_group_count != 1 )); then
  available_groups="$(jq -r '[.data[] | "\(.attributes.name) (\(if .attributes.isInternalGroup then "internal" else "external" end))"] | join(", ")' <<<"$groups_json")"
  if [[ -n "$beta_group_name" ]]; then
    fail "expected one TestFlight group named '${beta_group_name}', found ${matching_group_count}; available groups: ${available_groups:-none}"
  fi
  fail "expected one internal TestFlight group, found ${matching_group_count}; set --beta-group NAME; available groups: ${available_groups:-none}"
fi

beta_group_id="$(jq -r '.[0].id' <<<"$matching_groups")"
resolved_beta_group_name="$(jq -r '.[0].attributes.name' <<<"$matching_groups")"
encoded_beta_group_id="$(urlencode "$beta_group_id")"
group_builds_json="$(asc_request GET "/v1/betaGroups/${encoded_beta_group_id}/relationships/builds?limit=200")"
if jq -e --arg build_id "$build_id" '.data[]? | select(.id == $build_id)' <<<"$group_builds_json" >/dev/null; then
  log "Build ${next_build} is already assigned to '${resolved_beta_group_name}'"
else
  group_payload="$(jq -cn --arg build_id "$build_id" '{data:[{type:"builds",id:$build_id}]}')"
  asc_request POST "/v1/betaGroups/${encoded_beta_group_id}/relationships/builds" "$group_payload" >/dev/null
  log "Assigned build ${next_build} to '${resolved_beta_group_name}'"
fi

log "Beta setup complete: Plainstride ${marketing_version} (${next_build})"
fi

if [[ "$submit_public_release" == true ]]; then
  app_store_versions_json="$(asc_request GET "/v1/apps/${encoded_app_id}/appStoreVersions?filter%5Bplatform%5D=IOS&limit=200&fields%5BappStoreVersions%5D=versionString%2CappVersionState%2CreleaseType%2Cbuild")"
  matching_app_store_versions="$(jq -c --arg version "$marketing_version" '[.data[] | select(.attributes.versionString == $version)]' <<<"$app_store_versions_json")"
  app_store_version_count="$(jq 'length' <<<"$matching_app_store_versions")"
  (( app_store_version_count <= 1 )) || fail "found multiple iOS App Store versions named ${marketing_version}"

  desired_release_type="AFTER_APPROVAL"
  if [[ "$manual_release" == true ]]; then
    desired_release_type="MANUAL"
  fi

  if (( app_store_version_count == 0 )); then
    create_app_store_version_payload="$(jq -cn \
      --arg app_id "$app_id" \
      --arg version "$marketing_version" \
      --arg release_type "$desired_release_type" \
      '{data:{type:"appStoreVersions",attributes:{platform:"IOS",versionString:$version,releaseType:$release_type},relationships:{app:{data:{type:"apps",id:$app_id}}}}}')"
    created_app_store_version_json="$(asc_request POST "/v1/appStoreVersions" "$create_app_store_version_payload")"
    matching_app_store_versions="$(jq -c '[.data]' <<<"$created_app_store_version_json")"
    log "Created iOS App Store version ${marketing_version}"
  fi

  app_store_version_id="$(jq -r '.[0].id' <<<"$matching_app_store_versions")"
  app_store_version_state="$(jq -r '.[0].attributes.appVersionState // .[0].attributes.appStoreState // empty' <<<"$matching_app_store_versions")"
  current_release_type="$(jq -r '.[0].attributes.releaseType // empty' <<<"$matching_app_store_versions")"
  [[ -n "$app_store_version_state" ]] || fail "App Store version ${marketing_version} has no appVersionState"
  encoded_app_store_version_id="$(urlencode "$app_store_version_id")"

  app_store_build_json="$(asc_request GET "/v1/appStoreVersions/${encoded_app_store_version_id}/relationships/build")"
  attached_build_id="$(jq -r '.data.id // empty' <<<"$app_store_build_json")"
  public_submission_needed=false

  case "$app_store_version_state" in
    PREPARE_FOR_SUBMISSION)
      public_submission_needed=true
      ;;
    READY_FOR_REVIEW)
      public_submission_needed=true
      ;;
    WAITING_FOR_REVIEW|IN_REVIEW|PENDING_APPLE_RELEASE|PENDING_DEVELOPER_RELEASE|PROCESSING_FOR_DISTRIBUTION|READY_FOR_DISTRIBUTION|READY_FOR_SALE|ACCEPTED)
      [[ "$attached_build_id" == "$build_id" ]] || \
        fail "App Store version ${marketing_version} is ${app_store_version_state} with a different build attached"
      log "App Store version ${marketing_version} is already ${app_store_version_state} with build ${next_build}"
      ;;
    *)
      fail "App Store version ${marketing_version} cannot be submitted from state ${app_store_version_state}"
      ;;
  esac

  if [[ "$public_submission_needed" == true ]]; then
    if [[ "$app_store_version_state" == "READY_FOR_REVIEW" && "$attached_build_id" != "$build_id" ]]; then
      fail "App Store version ${marketing_version} is already ready for review with a different build attached"
    elif [[ "$attached_build_id" == "$build_id" ]]; then
      log "Build ${next_build} is already attached to App Store version ${marketing_version}"
    else
      build_linkage_payload="$(jq -cn --arg build_id "$build_id" '{data:{type:"builds",id:$build_id}}')"
      asc_request PATCH "/v1/appStoreVersions/${encoded_app_store_version_id}/relationships/build" "$build_linkage_payload" >/dev/null
      log "Attached build ${next_build} to App Store version ${marketing_version}"
    fi

    if [[ "$app_store_version_state" == "PREPARE_FOR_SUBMISSION" ]]; then
      app_store_localizations_json="$(asc_request GET "/v1/appStoreVersions/${encoded_app_store_version_id}/appStoreVersionLocalizations?limit=200&fields%5BappStoreVersionLocalizations%5D=locale%2CwhatsNew")"
      matching_app_store_localizations="$(jq -c --arg locale "$app_store_locale" '[.data[] | select(.attributes.locale == $locale)]' <<<"$app_store_localizations_json")"
      app_store_localization_count="$(jq 'length' <<<"$matching_app_store_localizations")"
      (( app_store_localization_count == 1 )) || \
        fail "expected one ${app_store_locale} localization for App Store version ${marketing_version}, found ${app_store_localization_count}"
      app_store_localization_id="$(jq -r '.[0].id' <<<"$matching_app_store_localizations")"
      current_app_store_notes="$(jq -r '.[0].attributes.whatsNew // empty' <<<"$matching_app_store_localizations")"

      if [[ "$current_app_store_notes" == "$app_store_release_notes" ]]; then
        log "App Store What's New already matches ${RELEASE_DOC}"
      else
        app_store_localization_payload="$(jq -cn \
          --arg id "$app_store_localization_id" \
          --arg whats_new "$app_store_release_notes" \
          '{data:{type:"appStoreVersionLocalizations",id:$id,attributes:{whatsNew:$whats_new}}}')"
        asc_request PATCH "/v1/appStoreVersionLocalizations/$(urlencode "$app_store_localization_id")" "$app_store_localization_payload" >/dev/null
        log "Published ${app_store_locale} App Store What's New"
      fi

      if [[ "$current_release_type" == "$desired_release_type" ]]; then
        log "App Store release type is already ${desired_release_type}"
      else
        release_type_payload="$(jq -cn \
          --arg id "$app_store_version_id" \
          --arg release_type "$desired_release_type" \
          '{data:{type:"appStoreVersions",id:$id,attributes:{releaseType:$release_type}}}')"
        asc_request PATCH "/v1/appStoreVersions/${encoded_app_store_version_id}" "$release_type_payload" >/dev/null
        log "Set App Store release type to ${desired_release_type}"
      fi
    elif [[ "$current_release_type" != "$desired_release_type" ]]; then
      fail "App Store version ${marketing_version} is ready for review with release type ${current_release_type:-unknown}, expected ${desired_release_type}"
    fi

    ready_submissions_json="$(asc_request GET "/v1/apps/${encoded_app_id}/reviewSubmissions?filter%5Bplatform%5D=IOS&filter%5Bstate%5D=READY_FOR_REVIEW&limit=2&fields%5BreviewSubmissions%5D=state")"
    ready_submission_count="$(jq '.data | length' <<<"$ready_submissions_json")"
    (( ready_submission_count <= 1 )) || fail "multiple iOS review submissions are ready; resolve them in App Store Connect"

    if (( ready_submission_count == 0 )); then
      review_submission_payload="$(jq -cn --arg app_id "$app_id" '{data:{type:"reviewSubmissions",relationships:{app:{data:{type:"apps",id:$app_id}}}}}')"
      review_submission_json="$(asc_request POST "/v1/reviewSubmissions" "$review_submission_payload")"
      review_submission_id="$(jq -r '.data.id // empty' <<<"$review_submission_json")"
      [[ -n "$review_submission_id" ]] || fail "App Store Connect did not return a review submission ID"
      log "Created App Store review submission"
    else
      review_submission_id="$(jq -r '.data[0].id' <<<"$ready_submissions_json")"
      log "Reusing the existing ready App Store review submission"
    fi

    encoded_review_submission_id="$(urlencode "$review_submission_id")"
    review_items_json="$(asc_request GET "/v1/reviewSubmissions/${encoded_review_submission_id}/items?limit=50&fields%5BreviewSubmissionItems%5D=state%2CappStoreVersion")"
    matching_review_item_count="$(jq --arg version_id "$app_store_version_id" '[.data[] | select(.relationships.appStoreVersion.data.id? == $version_id)] | length' <<<"$review_items_json")"
    other_app_version_item_count="$(jq --arg version_id "$app_store_version_id" '[.data[] | select(.relationships.appStoreVersion.data.id? != null and .relationships.appStoreVersion.data.id != $version_id)] | length' <<<"$review_items_json")"
    (( matching_review_item_count <= 1 )) || fail "App Store version ${marketing_version} appears multiple times in the review submission"
    (( other_app_version_item_count == 0 )) || fail "the ready review submission already contains a different App Store version"

    if (( matching_review_item_count == 0 )); then
      review_item_payload="$(jq -cn \
        --arg submission_id "$review_submission_id" \
        --arg version_id "$app_store_version_id" \
        '{data:{type:"reviewSubmissionItems",relationships:{reviewSubmission:{data:{type:"reviewSubmissions",id:$submission_id}},appStoreVersion:{data:{type:"appStoreVersions",id:$version_id}}}}}')"
      asc_request POST "/v1/reviewSubmissionItems" "$review_item_payload" >/dev/null
      log "Added App Store version ${marketing_version} to the review submission"
    else
      log "App Store version ${marketing_version} is already in the review submission"
    fi

    submit_review_payload="$(jq -cn \
      --arg submission_id "$review_submission_id" \
      '{data:{type:"reviewSubmissions",id:$submission_id,attributes:{submitted:true}}}')"
    asc_request PATCH "/v1/reviewSubmissions/${encoded_review_submission_id}" "$submit_review_payload" >/dev/null
    log "Submitted Plainstride ${marketing_version} (${next_build}) to App Review"
  fi

  if [[ "$manual_release" == true ]]; then
    log "Public release setup complete; release the approved version manually in App Store Connect"
  else
    log "Public release setup complete; Apple will release the version automatically after approval"
  fi
fi
