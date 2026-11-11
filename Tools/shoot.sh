#!/bin/zsh
# Shoots trailer footage in the iOS Simulator, then cuts the highlights.
#
#   ./Tools/shoot.sh <plan> [--build] [--fresh] [--no-cut]
#
# plan      all | scripted | cpu | comma-separated words a scene's name must contain
# --build   build the Release simulator app first (otherwise the last build is installed)
# --fresh   start the footage folder over (otherwise a run carries on past scenes already recorded)
# --no-cut  leave highlights.py for later
# --size WxH  the video's size, framed as a screen that shape frames it (default 1920x1080)
#
# The app is relaunched if it dies before writing `done`; each launch skips the scenes already recorded.
set -u
setopt NO_NOMATCH
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$(dirname "$0")/.."

PLAN=${1:?plan: all | scripted | cpu | words}; shift
BUILD=0; FRESH=0; CUT=1; SIZE_ARGS=""
while (( $# )); do
    case $1 in
        --build) BUILD=1 ;;
        --fresh) FRESH=1 ;;
        --no-cut) CUT=0 ;;
        --size) shift; SIZE_ARGS="-footageSize ${1:?--size WxH}" ;;
        *) echo "unknown flag $1"; exit 2 ;;
    esac
    shift
done

BUNDLE=com.sorsec0de.projectesper
DERIVED=/tmp/esper-dd-sim
APP=$DERIVED/Build/Products/Release-iphonesimulator/ProjectEsper.app
RELAUNCHES=6

# The simulator: whichever iPad's booted, else the iPad Pro 13-inch booted here.
UDID=${ESPER_SIM:-$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; d=[x for v in json.load(sys.stdin)["devices"].values() for x in v if "iPad" in x["name"]]; print(d[0]["udid"] if d else "")')}
if [[ -z $UDID ]]; then
    UDID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=[x for v in json.load(sys.stdin)["devices"].values() for x in v if x["name"].startswith("iPad Pro 13-inch")]; print(d[0]["udid"])')
    xcrun simctl boot "$UDID"
fi
echo "simulator $UDID"

if (( BUILD )); then
    xcodebuild -project ProjectEsper.xcodeproj -scheme ProjectEsper -configuration Release \
        -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DERIVED" build -quiet || exit 1
fi
xcrun simctl install "$UDID" "$APP" || exit 1

DATA=$(xcrun simctl get_app_container "$UDID" $BUNDLE data)
FOLDER="$DATA/tmp/Footage"
if (( FRESH )); then rm -rf "$FOLDER"; fi
mkdir -p "$FOLDER"
rm -f "$FOLDER/done"

for (( launch = 0; launch <= RELAUNCHES; launch++ )); do
    xcrun simctl terminate "$UDID" $BUNDLE 2>/dev/null
    PID=$(xcrun simctl launch "$UDID" $BUNDLE -footage "$PLAN" ${=SIZE_ARGS} | sed 's/.*: //')
    echo "launch $launch pid $PID $(date +%H:%M:%S)"
    while kill -0 "$PID" 2>/dev/null && [[ ! -f "$FOLDER/done" ]]; do sleep 2; done
    if [[ -f "$FOLDER/done" ]]; then break; fi
    echo "the app died $(date +%H:%M:%S); recorded so far: $(ls "$FOLDER" | grep -c '\.mp4$')"
    sleep 3
done
[[ -f "$FOLDER/done" ]] || { echo "gave up after $RELAUNCHES relaunches"; exit 1; }
echo "done: $(ls "$FOLDER" | grep -c '\.mp4$') videos in $FOLDER"
if (( CUT )); then exec ./Tools/highlights.py; fi
exit 0
