pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils
import "../utils/scripts/skwd-wall.js" as Adapter

Singleton {
    id: root

    property var entries: []
    property var outputs: []
    property bool initialized: false
    property bool available: false
    property string error: ""
    readonly property bool applying: applyProcess.running
    readonly property bool hasSelection: outputs.some(o => o.connected !== false && (o.path || o.we_id || o.current))
    readonly property bool animated: outputs.some(o => Adapter.animated(o))
    readonly property string selected: {
        const output = outputs.find(o => Adapter.animated(o)) || outputs.find(o => o.connected !== false);
        return Adapter.selection(output, entries);
    }

    Component {
        id: wallpaperEntry
        QtObject {
            required property string path
            required property string skwdKey
            required property string name
            required property string relativePath
            required property string parentDir
            required property string mediaType
            required property string mediaPath
            required property string thumbnail
        }
    }

    signal applied(string path)

    function entry(path: string): var {
        return entries.find(w => w.path === path);
    }

    function animatedOn(screenName: string): bool {
        return outputs.some(o => o.name === screenName && Adapter.animated(o));
    }

    function apply(path: string): void {
        if (applying) return;
        currentProcess.running = false;
        error = "";
        applyProcess.path = path;
        applyProcess.command = ["sh", "-c", 'exec skwd-helm apply "$1"', "--", path.startsWith("skwd:") ? path.slice(5) : path];
        applyProcess.running = true;
    }

    function refresh(): void {
        if (!currentProcess.running && !applying) currentProcess.running = true;
    }

    Process {
        id: libraryProcess
        command: ["sh", "-c", "exec skwd-helm list --json"]
        running: true
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: code => {
            if (code !== 0) return;
            try {
                const rows = Adapter.library(JSON.parse(stdout.text), Paths.wallsdir);
                const previous = root.entries;
                root.entries = rows.map(row => wallpaperEntry.createObject(root, row));
                Qt.callLater(() => { for (const entry of previous) entry.destroy(); });
            } catch (e) { Logger.log("[skwd-wall] " + e.message); }
        }
    }

    Process {
        id: currentProcess
        command: ["sh", "-c", "exec skwd-helm current --json"]
        running: true
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: code => {
            if (root.applying) return;
            root.available = code === 0;
            if (code === 0) {
                try {
                    const outputs = JSON.parse(stdout.text).outputs;
                    if (!Array.isArray(outputs)) throw new Error("Missing output list");
                    if (JSON.stringify(outputs) !== JSON.stringify(root.outputs)) root.outputs = outputs;
                } catch (e) { root.available = false; Logger.log("[skwd-wall] " + e.message); }
            }
            if (!root.available) root.outputs = [];
            root.initialized = true;
        }
    }

    Process {
        id: applyProcess
        property string path: ""
        stderr: StdioCollector {}
        onExited: code => {
            if (code === 0) {
                root.applied(path);
            } else {
                root.error = stderr.text.trim() || qsTr("Could not apply wallpaper. Check that skwd-walld is running.");
                Quickshell.execDetached(["notify-send", "Caelestia wallpaper", root.error]);
            }
            root.refresh();
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: { if (!libraryProcess.running) libraryProcess.running = true; }
    }
}
