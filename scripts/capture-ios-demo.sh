#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_dir=${script_dir:h}
output_dir=${1:-"$repo_dir/artifacts/ios-demo"}
requested_simulator_id=${2:-}
derived_data_path="/tmp/plainstride-demo-capture-derived"
build_log="$output_dir/xcodebuild.log"
recording_video="$output_dir/.plainstride-demo-recording.mp4"
raw_video="$output_dir/plainstride-demo-raw.mp4"
social_video="$output_dir/plainstride-demo-social.mp4"
loop_video="$output_dir/plainstride-demo-loop.mp4"
loop_gif="$output_dir/plainstride-demo-loop.gif"
test_identifier="OutboundUITests/OutboundUITests/testDemoCaptureHarvestHalfMarathon"

mkdir -p "$output_dir"

if [[ -n "$requested_simulator_id" ]]; then
  simulator_id=$requested_simulator_id
else
  simulator_id=$(xcrun simctl list devices available | awk '
    /iPhone/ && /Booted/ {
      for (field = 1; field <= NF; field++) {
        if ($field ~ /^\([0-9A-F-]{36}\)$/) {
          gsub(/[()]/, "", $field)
          print $field
          exit
        }
      }
    }
  ')
  if [[ -z "$simulator_id" ]]; then
    simulator_id=$(xcrun simctl list devices available | awk '
      /iPhone/ && /Shutdown/ {
        for (field = 1; field <= NF; field++) {
          if ($field ~ /^\([0-9A-F-]{36}\)$/) {
            gsub(/[()]/, "", $field)
            print $field
            exit
          }
        }
      }
    ')
  fi
fi

[[ -n "$simulator_id" ]] || { print "No available iPhone Simulator was found." >&2; exit 1; }
command -v ffmpeg >/dev/null || { print "ffmpeg is required to create the derived video exports." >&2; exit 1; }

print "Preparing Plainstride demo capture on $simulator_id..."
xcrun simctl boot "$simulator_id" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl uninstall "$simulator_id" plainstride.outbound >/dev/null 2>&1 || true
xcrun simctl status_bar "$simulator_id" override \
  --time 9:41 \
  --operatorName Plainstride \
  --wifiBars 3 \
  --cellularBars 4 \
  --batteryLevel 100 \
  --batteryState charged

cleanup() {
  if [[ -n "${recorder_pid:-}" ]] && kill -0 "$recorder_pid" >/dev/null 2>&1; then
    kill -INT "$recorder_pid" >/dev/null 2>&1 || true
    wait "$recorder_pid" >/dev/null 2>&1 || true
  fi
  xcrun simctl status_bar "$simulator_id" clear >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

cd "$repo_dir"
print "Building the app and demo UI test..."
xcodebuild -quiet \
  -project ios/Outbound/Outbound.xcodeproj \
  -scheme OutboundAppTests \
  -destination "id=$simulator_id" \
  -derivedDataPath "$derived_data_path" \
  OUTBOUND_APP_TEST_MODE=YES \
  -parallel-testing-enabled NO \
  build-for-testing

app_path="$derived_data_path/Build/Products/Debug-iphonesimulator/Outbound.app"
[[ -d "$app_path" ]] || { print "Built app was not found at $app_path" >&2; exit 1; }
xcrun simctl install "$simulator_id" "$app_path"
xcrun simctl privacy "$simulator_id" grant motion plainstride.outbound
xcrun simctl privacy "$simulator_id" grant location plainstride.outbound

print "Launching the Harvest Half Marathon story..."
xcodebuild -quiet \
  -project ios/Outbound/Outbound.xcodeproj \
  -scheme OutboundAppTests \
  -destination "id=$simulator_id" \
  -derivedDataPath "$derived_data_path" \
  OUTBOUND_APP_TEST_MODE=YES \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 90 \
  -maximum-test-execution-time-allowance 120 \
  -only-testing:"$test_identifier" \
  test-without-building >"$build_log" 2>&1 &
test_pid=$!

for _ in {1..120}; do
  if pgrep -f "$simulator_id.*Outbound.app/Outbound" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$test_pid" >/dev/null 2>&1; then
    wait "$test_pid" || { tail -n 80 "$build_log" >&2; exit 1; }
  fi
  sleep 0.25
done

print "Recording the Simulator..."
xcrun simctl io "$simulator_id" recordVideo --codec=h264 --force "$recording_video" >/dev/null 2>&1 &
recorder_pid=$!

set +e
wait "$test_pid"
test_status=$?
set -e
kill -INT "$recorder_pid" >/dev/null 2>&1 || true
wait "$recorder_pid" >/dev/null 2>&1 || true
recorder_pid=""

if (( test_status != 0 )); then
  tail -n 100 "$build_log" >&2
  exit "$test_status"
fi

print "Creating framed and looping exports..."
recording_duration=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$recording_video")
trimmed_duration=$(( recording_duration - 6.0 ))
ffmpeg -hide_banner -loglevel error -y -ss 2 -i "$recording_video" -t "$trimmed_duration" \
  -an -vf "fps=30" -c:v libx264 -crf 18 -preset medium -pix_fmt yuv420p -movflags +faststart "$raw_video"
rm -f "$recording_video"

ffmpeg -hide_banner -loglevel error -y -i "$raw_video" \
  -filter_complex "[0:v]split=2[background][foreground];[background]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,gblur=sigma=42,eq=brightness=-0.22:saturation=0.85[canvas];[foreground]scale=-2:1720[app];[canvas]drawbox=x=104:y=70:w=872:h=1780:color=white@0.16:t=fill[frame];[frame][app]overlay=(W-w)/2:(H-h)/2:format=auto" \
  -an -c:v libx264 -crf 19 -preset medium -pix_fmt yuv420p -movflags +faststart "$social_video"

ffmpeg -hide_banner -loglevel error -y -ss 14 -t 8 -i "$social_video" \
  -an -c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p -movflags +faststart "$loop_video"

palette_path="$output_dir/demo-loop-palette.png"
ffmpeg -hide_banner -loglevel error -y -i "$loop_video" \
  -vf "fps=12,scale=360:-2:flags=lanczos,palettegen=max_colors=128" "$palette_path"
ffmpeg -hide_banner -loglevel error -y -i "$loop_video" -i "$palette_path" \
  -lavfi "fps=12,scale=360:-2:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer" -loop 0 "$loop_gif"
rm -f "$palette_path"

print "Capture complete:"
print "  Raw:    $raw_video"
print "  Social: $social_video"
print "  Loop:   $loop_video"
print "  GIF:    $loop_gif"
