pragma Singleton

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.Models
import qs.services
import qs.utils

Searcher {
    id: root

    readonly property string currentNamePath: `${Paths.state}/wallpaper/path.txt`
    readonly property string fallback: Quickshell.shellPath("assets/wallpaper.webp")

    property bool previousWallpaperEnabledState: false
    readonly property bool previewing: previewPath !== ""
    readonly property string current: previewing ? previewPath : actualCurrent
    property string previewPath
    property string actualCurrent
    property var videoThumbs: ({})
    property var videoThumbsPending: ({})

    property string storedWallpaper: ""
    property bool storedWallpaperLoaded: false

    function mediaType(w: var): string {
        return w.mediaType || (Images.isVideo(w.name) ? "video" : Images.isAnimated(w.name) ? "animated" : "static");
    }

    function externalOn(screenName: string): bool {
        return !previewing && SkwdWall.animatedOn(screenName);
    }

    function displayPath(path: string): string {
        const entry = SkwdWall.entry(path);
        return entry ? (entry.mediaType === "static" ? entry.mediaPath || entry.thumbnail : entry.thumbnail) : path.startsWith("skwd:") ? "" : path;
    }

    function backgroundPath(screenName: string): string {
        if (!previewing) {
            const output = SkwdWall.outputs.find(o => o.name === screenName && o.connected !== false);
            if (output && output.type === "static" && output.path) return output.path;
        }
        return displayPath(current);
    }

    function restoreStoredWallpaper(): void {
        if (!storedWallpaperLoaded || !SkwdWall.initialized || SkwdWall.applying) return;
        if (SkwdWall.hasSelection) {
            actualCurrent = SkwdWall.selected;
            return;
        }
        if (storedWallpaper.startsWith("skwd:")) {
            actualCurrent = storedWallpaper;
            return;
        }
        actualCurrent = storedWallpaper || fallback;
        if (!storedWallpaper)
            Quickshell.execDetached(["caelestia", "wallpaper", "-f", fallback, ...Colours.smartArg]);
        if (!Images.isVideo(actualCurrent)) syncPlasmaWallpaper(actualCurrent);
    }

    property string currentMediaFilter: "All"

    property var filteredList: {
        const res = (wallpapers.entries || []).concat(SkwdWall.entries);
        if (currentMediaFilter === "Image") {
            return res.filter(w => mediaType(w) === "static");
        } else if (currentMediaFilter === "Video") {
            return res.filter(w => mediaType(w) === "video");
        } else if (currentMediaFilter === "Animated") {
            return res.filter(w => ["animated", "we"].includes(mediaType(w)));
        }
        return res;
    }

    readonly property var categories: {
        let dummy = root.list;
        const baseDir = Paths.wallsdir;
        let cats = [];
        for (let i = 0; i < root.list.length; i++) {
            let p = root.list[i].parentDir;
            if (p !== baseDir) {
                let cat = p.slice(baseDir.length + 1);
                if (cat.includes("/")) cat = cat.slice(0, cat.indexOf("/"));
                if (!cats.includes(cat)) cats.push(cat);
            }
        }
        return ["Main"].concat(cats.sort());
    }

    readonly property var grouped: {
        let dummy = root.list;
        const baseDir = Paths.wallsdir;
        let grp = { "Main": [] };
        for (let i = 0; i < root.list.length; i++) {
            let w = root.list[i];
            let p = w.parentDir;
            if (p === baseDir) {
                grp["Main"].push(w);
            } else {
                let cat = p.slice(baseDir.length + 1);
                if (cat.includes("/")) cat = cat.slice(0, cat.indexOf("/"));
                if (!grp[cat]) grp[cat] = [];
                grp[cat].push(w);
            }
        }
        return grp;
    }

    function getCategoryFor(w: var): string {
        let category = w.parentDir.slice(Paths.wallsdir.length + 1);
        if (category.includes("/"))
            category = category.slice(0, category.indexOf("/"));
        return category;
    }

    function setRandom(): void {
        if (!root.list || root.list.length === 0) return;
        let idx = Math.floor(Math.random() * root.list.length);
        if (root.list.length > 1 && root.list[idx].path === actualCurrent)
            idx = (idx + 1) % root.list.length;
        setWallpaper(root.list[idx].path);
    }

    function setNextSequential(): void {
        if (!root.list || root.list.length === 0) return;
        let idx = -1;
        for (let i = 0; i < root.list.length; i++) {
            if (root.list[i].path === actualCurrent) {
                idx = i;
                break;
            }
        }
        idx = (idx + 1) % root.list.length;
        setWallpaper(root.list[idx].path);
    }

    function next(): void {
        if (GlobalConfig.background.slideshowRandom) {
            setRandom();
        } else {
            setNextSequential();
        }
    }

    function setWallpaper(path: string): void {
        if (SkwdWall.applying) return;
        if (path.startsWith("skwd:") || (SkwdWall.available && Images.isVideo(path))) {
            SkwdWall.apply(path);
            return;
        }

        if (previewing && path !== actualCurrent)
            previewColoursState.hold();
        actualCurrent = path;
        if (Images.isVideo(path)) {
            const thumb = thumbFor(path);
            if (thumb !== "") {
                const script = 'caelestia wallpaper -f "$1" --apply-path "$2" ' + Colours.smartArg.join(" ") + '; printf "%s" "$2" > "$3"';
                Quickshell.execDetached(["sh", "-c", script, "--", thumb, path, root.currentNamePath]);
                syncPlasmaWallpaper(thumb);
            } else {
                Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" > "$2"', "--", path, root.currentNamePath]);
            }
        } else {
            Quickshell.execDetached(["caelestia", "wallpaper", "-f", path, ...Colours.smartArg]);
            syncPlasmaWallpaper(path);
        }
    }

    function syncPlasmaWallpaper(imagePath: string): void {
        if (!imagePath || imagePath.startsWith("skwd:") || SkwdWall.animated)
            return;
        const script = 'var allDesktops = desktops();' +
            'for (var i = 0; i < allDesktops.length; i++) {' +
            '    var d = allDesktops[i];' +
            '    d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];' +
            '    d.writeConfig("Image", "file://" + ' + JSON.stringify(imagePath) + ');' +
            '}';
        Quickshell.execDetached(["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", script]);

        if (GlobalConfig.lock.syncWallpaper)
            Quickshell.execDetached(["kwriteconfig6", "--file", "kscreenlockerrc", "--group", "Greeter", "--group", "Wallpaper", "--group", "org.kde.image", "--group", "General", "--key", "Image", "file://" + imagePath]);
    }

    function preview(path: string): void {
        if (!previewing) {
            previousWallpaperEnabledState = GlobalConfig.background.wallpaperEnabled;
            GlobalConfig.background.wallpaperEnabled = true;
        }

        previewPath = path;
        previewColourOf(path);
    }

    function previewColourOf(path: string): void {
        if (Colours.scheme !== "dynamic")
            return;
        const thumb = thumbFor(path);
        if (thumb) previewColoursState.show(thumb);
    }

    function stopPreview(): void {
        if (previewing) {
            GlobalConfig.background.wallpaperEnabled = previousWallpaperEnabledState;
        }

        previewPath = "";
        previewColoursState.stop();
    }

    function getThumbnailPath(path: string): string {
        if (Images.isVideo(path)) {
            return `${Paths.cache}/wallpapers/${CUtils.sha256(path)}/first_frame.png`;
        }
        return path;
    }

    function thumbFor(path: string): string {
        if (path.startsWith("skwd:")) return SkwdWall.entry(path)?.thumbnail || "";
        const p = String(path || "").replace(/^file:\/\//, "");
        if (p === "" || !Images.isVideo(p))
            return p;
        if (root.videoThumbs[p])
            return root.videoThumbs[p];
        requestVideoThumb(p);
        return "";
    }

    function requestVideoThumb(path: string): void {
        if (root.videoThumbsPending[path] || root.videoThumbs[path])
            return;
        const pending = root.videoThumbsPending;
        pending[path] = true;
        root.videoThumbsPending = pending;

        const out = getThumbnailPath(path);
        const script = 'out="$1"; src="$2"; [ -s "$out" ] || { mkdir -p "$(dirname "$out")"; ' +
                       'ffmpeg -y -loglevel error -i "$src" -vf "thumbnail,scale=640:-1" -frames:v 1 "$out" >/dev/null 2>&1; }; ' +
                       'printf "%s" "$src" > "$(dirname "$out")/source_path"; ' +
                       '[ -s "$out" ] && printf %s "$out"';
        const qml = 'import QtQuick\nimport Quickshell.Io\n' +
            'Process {\n' +
            '    id: p\n' +
            '    command: ' + JSON.stringify(["sh", "-c", script, "--", out, path]) + '\n' +
            '    stdout: StdioCollector { onStreamFinished: root.onVideoThumb(' + JSON.stringify(path) + ', (text || "").trim(), p); }\n' +
            '    onExited: code => { if (code !== 0) p.destroy(); }\n' +
            '}';
        try {
            const o = Qt.createQmlObject(qml, root, "videoThumbProc");
            o.running = true;
        } catch (e) {
            Logger.log("[wallpapers] video thumbnail error: " + e.message);
        }
    }

    function onVideoThumb(path: string, out: string, proc: var): void {
        if (out !== "") {
            const m = root.videoThumbs;
            m[path] = out;
            root.videoThumbs = Object.assign({}, m);
            if (path === root.actualCurrent && !SkwdWall.animated) {
                const script = 'caelestia wallpaper -f "$1" --apply-path "$2" ' + Colours.smartArg.join(" ") + '; printf "%s" "$2" > "$3"';
                Quickshell.execDetached(["sh", "-c", script, "--", out, path, root.currentNamePath]);
                syncPlasmaWallpaper(out);
            }
            if (path === root.previewPath && root.previewing)
                root.previewColourOf(path);
        }
        const pending = root.videoThumbsPending;
        delete pending[path];
        root.videoThumbsPending = pending;
        if (proc)
            proc.destroy();
    }

    list: filteredList
    key: "relativePath"
    useFuzzy: GlobalConfig.launcher.useFuzzy.wallpapers
    extraOpts: useFuzzy ? ({}) : ({
            forward: false
        })

    IpcHandler {
        function get(): string {
            return root.actualCurrent;
        }

        function set(path: string): void {
            root.setWallpaper(path);
        }

        function list(): string {
            return root.list.map(w => w.path).join("\n");
        }

        target: "wallpaper"
    }

    FileView {
        path: root.currentNamePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const wall = text().trim();
            if (Images.isVideo(root.actualCurrent) && wall === root.getThumbnailPath(root.actualCurrent)) return;
            root.storedWallpaper = wall;
            root.storedWallpaperLoaded = true;
            root.restoreStoredWallpaper();
        }
        onLoadFailed: {
            root.storedWallpaperLoaded = true;
            root.restoreStoredWallpaper();
        }
    }

    Connections {
        target: SkwdWall
        function onInitializedChanged(): void { root.restoreStoredWallpaper(); }
        function onSelectedChanged(): void {
            if (SkwdWall.selected) root.actualCurrent = SkwdWall.selected;
        }
        function onApplied(path: string): void {
            if (root.previewing) previewColoursState.hold();
            root.actualCurrent = path;
        }
    }

    FileSystemModel {
        id: wallpapers

        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Files
        nameFilters: Images.validImageExtensions.concat(Images.validVideoExtensions).map(e => `*.${e}`)
    }

    PreviewColours {
        id: previewColoursState
    }
}
