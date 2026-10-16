function library(payload, baseDir) {
    if (!Array.isArray(payload.wallpapers)) throw new Error("Missing wallpaper list");
    return payload.wallpapers.filter(w => w.key && !w.hidden && ["static", "video", "we"].includes(w.type)).map(w => ({
        path: "skwd:" + w.key,
        skwdKey: w.key,
        name: w.name || w.key,
        relativePath: "Skwd Wall/" + (w.name || w.key),
        parentDir: baseDir + "/Skwd Wall",
        mediaType: w.type,
        mediaPath: w.video_file || w.path || "",
        thumbnail: w.thumb || w.preview || ""
    }));
}

function animated(output) {
    return output && output.connected !== false && ["we", "video"].includes(output.type) && !!(output.path || output.we_id || output.current);
}

function selection(output, entries) {
    if (!output) return "";
    const entry = entries.find(w => w.skwdKey === output.current ||
        (output.we_id && w.skwdKey === "we:" + output.we_id) ||
        (output.path && w.mediaPath === output.path));
    return entry ? entry.path : output.we_id ? "skwd:we:" + output.we_id : output.path || "";
}
