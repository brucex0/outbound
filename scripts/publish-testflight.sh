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
ASC_API_BASE_URL="https://api.appstoreconnect.apple.com"

dry_run=false
commit_changes=true
configure_beta=true
beta_setup_only=false
requested_build=""
beta_group_name="${BETA_GROUP:-}"
beta_locale="${BETA_LOCALE:-en-US}"
asc_processing_timeout="${ASC_PROCESSING_TIMEOUT:-3600}"
asc_poll_interval="${ASC_POLL_INTERVAL:-30}"

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
          [--beta-group NAME] [--beta-setup-only | --skip-beta-setup]

Increment Plainstride's build number, compile the Release configuration,
commit the verified metadata, create an App Store archive, and upload it to
App Store Connect. After processing, populate the build's release notes and
assign it to a TestFlight beta group.

Options:
  --dry-run              Print the planned version without changing anything.
  --no-commit            Do not commit the verified build-number changes.
  --build-number NUMBER  Use NUMBER instead of incrementing by one. NUMBER may
                         equal the current build to publish prepared metadata.
  --beta-group NAME      Assign the build to this exact TestFlight group name.
                         If omitted, the sole internal group is selected.
  --beta-setup-only      Configure release notes and testers for an existing
                         build without compiling, archiving, or uploading.
  --skip-beta-setup      Upload without release notes or group assignment.
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
  ASC_PROCESSING_TIMEOUT  Seconds to wait for processing. Defaults to 3600.
  ASC_POLL_INTERVAL      Poll interval in seconds. Defaults to 30.

The beta setup requires an App Store Connect API key. External groups may still
require Apple's Beta App Review before their testers receive the build.
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
    --beta-group)
      shift
      [[ $# -gt 0 ]] || fail "--beta-group requires a value"
      beta_group_name="$1"
      ;;
    --beta-setup-only)
      beta_setup_only=true
      ;;
    --skip-beta-setup)
      configure_beta=false
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

if [[ "$beta_setup_only" == true && "$configure_beta" == false ]]; then
  fail "--beta-setup-only and --skip-beta-setup cannot be used together"
fi

cd "$ROOT_DIR"

for tool in curl git jq ruby xcodebuild plutil; do
  command -v "$tool" >/dev/null 2>&1 || fail "required tool not found: $tool"
done

[[ "$asc_processing_timeout" =~ ^[1-9][0-9]*$ ]] || \
  fail "ASC_PROCESSING_TIMEOUT must be a positive integer"
[[ "$asc_poll_interval" =~ ^[1-9][0-9]*$ ]] || \
  fail "ASC_POLL_INTERVAL must be a positive integer"
[[ -n "$beta_locale" ]] || fail "BETA_LOCALE must not be empty"

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

if [[ "$dry_run" == false && "$configure_beta" == true && "$use_asc_api_key" == false ]]; then
  fail "automatic beta setup requires ASC_KEY_PATH, ASC_KEY_ID, and ASC_ISSUER_ID (or the configured local key); use --skip-beta-setup to upload only"
fi

[[ -f "$PROJECT_FILE" ]] || fail "Xcode project file not found: $PROJECT_FILE"
[[ -f "$RELEASE_DOC" ]] || fail "release document not found: $RELEASE_DOC"

release_notes="$({ RELEASE_DOC="$RELEASE_DOC" ruby <<'RUBY'
path = ENV.fetch("RELEASE_DOC")
text = File.read(path)
match = text.match(/^### Beta Release Notes\s*$\n(.*?)(?=^###?\s|\z)/m)
abort "release document is missing a Beta Release Notes section" unless match
notes = match[1].strip
abort "Beta Release Notes must not be empty" if notes.empty?
abort "Beta Release Notes exceed App Store Connect's 4,000-character limit" if notes.length > 4_000
puts notes
RUBY
  } 2>&1)" || fail "$release_notes"

if [[ "$dry_run" == false && "$beta_setup_only" == false && -n "$(git status --porcelain --untracked-files=no)" ]]; then
  fail "tracked files are already modified; commit or stash them before publishing"
elif [[ "$dry_run" == true && "$beta_setup_only" == false && -n "$(git status --porcelain --untracked-files=no)" ]]; then
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
  if [[ "$beta_setup_only" == false ]]; then
    (( next_build >= current_build )) || fail "new build number must not be lower than $current_build"
  fi
elif [[ "$beta_setup_only" == true ]]; then
  next_build="$current_build"
else
  next_build="$((current_build + 1))"
  (( next_build > current_build )) || fail "new build number must be greater than $current_build"
fi

if [[ "$beta_setup_only" == true ]]; then
  log "Plainstride ${marketing_version}: configuring existing build ${next_build}"
elif (( next_build == current_build )); then
  log "Plainstride ${marketing_version}: using prepared build ${current_build}"
else
  log "Plainstride ${marketing_version}: build ${current_build} -> ${next_build}"
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

if [[ "$dry_run" == true ]]; then
  log "Dry run complete; no files changed"
  exit 0
fi

if [[ "$beta_setup_only" == false ]]; then
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
else
  log "Skipping compile, archive, and upload for existing build ${next_build}"
fi

if [[ "$configure_beta" == false ]]; then
  log "Skipped release notes and beta group assignment"
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
