#!/usr/bin/env bash
# suite: isolated
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v qs >/dev/null; then
    printf 'SKIP: qs is required for the skwd service runtime test\n'
    exit 0
fi
sandbox="$(mktemp -d)"
trap 'rm -rf -- "$sandbox"' EXIT
mkdir -p "$sandbox"/{services,utils/scripts,bin,runtime,cache,config,state}
chmod 700 "$sandbox/runtime"
cp "$repo_root/shell/services/SkwdWall.qml" "$sandbox/services/"
cp "$repo_root/shell/utils/scripts/"{skwd-wall,fzf,fuzzysort}.js "$sandbox/utils/scripts/"
cp "$repo_root/shell/utils/Searcher.qml" "$sandbox/utils/"
cat > "$sandbox/utils/Paths.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject { readonly property string wallsdir: "/walls" }
QML
cat > "$sandbox/utils/Logger.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject { function log(message) { console.log(message); } }
QML
cat > "$sandbox/library.json" <<'JSON'
{"wallpapers":[{"key":"we:42","type":"we","name":"Scene","we_id":"42","thumb":"/cache/42.webp"},{"key":"we:43","type":"video","name":"Workshop video","video_file":"/workshop/43/movie.mp4"},{"key":"static:a.jpg","type":"static","name":"a.jpg","path":"/walls/a.jpg"}]}
JSON
cat > "$sandbox/outputs.json" <<'JSON'
{"outputs":[{"name":"DP-1","type":"static","path":"/walls/a.jpg"},{"name":"HDMI-A-1","type":"static","path":"/walls/a.jpg"}]}
JSON
cat > "$sandbox/bin/skwd-helm" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
    list) cat "$SKWD_TEST_DIR/library.json" ;;
    current) cat "$SKWD_TEST_DIR/outputs.json" ;;
    apply)
        case "$2" in
            we:42) output='{"name":"DP-1","type":"we","we_id":"42"}' ;;
            /movie.mp4) output='{"name":"DP-1","type":"video","path":"/movie.mp4"}' ;;
            static:a.jpg) output='{"name":"DP-1","type":"static","path":"/walls/a.jpg"}' ;;
            *) printf 'wallpaper not found\n' >&2; exit 2 ;;
        esac
        printf '{"outputs":[%s,{"name":"HDMI-A-1","type":"static","path":"/walls/a.jpg"}]}' "$output" > "$SKWD_TEST_DIR/outputs.json"
        ;;
esac
SH
printf '#!/bin/sh\nexit 0\n' > "$sandbox/bin/notify-send"
chmod +x "$sandbox/bin/"*
cat > "$sandbox/shell.qml" <<'QML'
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.utils
ShellRoot {
    id: root
    property Searcher builtins: Searcher {
        list: [QtObject { property string name: "Variant" }]
    }
    property Searcher libraryFinder: Searcher {
        list: SkwdWall.entries
        key: "relativePath"
    }
    property int phase: 0
    function check(condition, message) {
        if (!condition) { console.error("SKWD_TEST_FAIL", message); Qt.quit(); }
        return condition;
    }
    Timer {
        interval: 25
        running: true
        repeat: true
        onTriggered: {
            if (root.phase === 0 && SkwdWall.initialized && SkwdWall.entries.length === 3) {
                if (!root.check(SkwdWall.available && !SkwdWall.animated && SkwdWall.selected === "skwd:static:a.jpg", "initial selection")) return;
                if (!root.check(root.builtins.query("Variant").length === 1, "inline launcher object list")) return;
                if (!root.check(root.libraryFinder.query("Skwd Wall").length === 3, "native wallpaper object list")) return;
                root.libraryFinder.useFuzzy = true;
                if (!root.check(root.libraryFinder.query("Skwd Wall").length === 3, "native wallpaper fuzzy search")) return;
                root.phase = 1;
                SkwdWall.apply("skwd:we:42");
            } else if (root.phase === 1 && !SkwdWall.applying && SkwdWall.animated) {
                if (!root.check(SkwdWall.selected === "skwd:we:42" && SkwdWall.animatedOn("DP-1") && !SkwdWall.animatedOn("HDMI-A-1"), "scene monitor ownership")) return;
                root.phase = 2;
                SkwdWall.apply("skwd:missing");
            } else if (root.phase === 2 && !SkwdWall.applying && SkwdWall.error !== "") {
                if (!root.check(SkwdWall.selected === "skwd:we:42", "failed apply changed selection")) return;
                root.phase = 3;
                SkwdWall.apply("/movie.mp4");
            } else if (root.phase === 3 && !SkwdWall.applying && SkwdWall.selected === "/movie.mp4") {
                if (!root.check(SkwdWall.animated && SkwdWall.error === "", "video playback state")) return;
                root.phase = 4;
                SkwdWall.apply("skwd:static:a.jpg");
            } else if (root.phase === 4 && !SkwdWall.applying && !SkwdWall.animated) {
                if (!root.check(SkwdWall.selected === "skwd:static:a.jpg", "return to static wallpaper")) return;
                root.phase = 5;
                externalPicker.running = true;
            } else if (root.phase === 5 && SkwdWall.selected === "skwd:we:42" && SkwdWall.animated) {
                console.log("SKWD_SERVICE_TEST_PASS");
                Qt.quit();
            }
        }
    }
    Process {
        id: externalPicker
        command: ["skwd-helm", "apply", "we:42"]
        onExited: SkwdWall.refresh()
    }
    Timer { interval: 10000; running: true; onTriggered: { console.error("SKWD_TEST_FAIL timeout", root.phase); Qt.quit(); } }
}
QML
if ! env QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR="$sandbox/runtime" \
    XDG_CACHE_HOME="$sandbox/cache" XDG_CONFIG_HOME="$sandbox/config" XDG_STATE_HOME="$sandbox/state" \
    SKWD_TEST_DIR="$sandbox" PATH="$sandbox/bin:$PATH" \
    timeout 15 qs -p "$sandbox" --no-color > "$sandbox/log" 2>&1; then
    cat "$sandbox/log"
    exit 1
fi
if ! rg -q 'SKWD_SERVICE_TEST_PASS' "$sandbox/log" || rg -q 'SKWD_TEST_FAIL' "$sandbox/log"; then
    cat "$sandbox/log"
    exit 1
fi
printf 'skwd QML service runtime tests passed\n'
