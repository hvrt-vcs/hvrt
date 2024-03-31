const std = @import("std");
const builtin = @import("builtin");

/// Roughly and poorly ported from Python stdlib: https://github.com/python/cpython/blob/3.12/Lib/tempfile.py#L156
pub fn getTempDir(alloc: std.mem.Allocator) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    var arena_alloc = arena.allocator();

    var dirlist2 = std.ArrayList([]const u8).init(arena_alloc);
    defer dirlist2.deinit();

    // First, try the environment.
    const envnames = [_][:0]const u8{ "TMPDIR", "TEMP", "TMP" };
    for (envnames) |envname| {
        const dirname = std.process.getEnvVarOwned(arena_alloc, envname) catch continue;
        try dirlist2.append(dirname);
    }

    // Failing that, try OS-specific locations.
    if (builtin.os.tag == .windows) {
        const os_locs = [_][]const u8{ "c:\\temp", "c:\\tmp", "\\temp", "\\tmp" };
        try dirlist2.appendSlice(&os_locs);
    } else {
        const os_locs = [_][]const u8{ "/tmp", "/var/tmp", "/usr/tmp" };
        try dirlist2.appendSlice(&os_locs);
    }

    if (std.process.getCwdAlloc(arena_alloc)) |cwd| {
        try dirlist2.append(cwd);
    } else |_| {}

    // We assume that if we can open one of the temp directories gathered
    // above, we can create files within it. Simply close the `Dir` object and
    // return the path.
    for (dirlist2.items) |tmp_path| {
        var tmp_dir = std.fs.openDirAbsolute(tmp_path, .{}) catch continue;
        tmp_dir.close();

        return try alloc.dupe(u8, tmp_path);
    }

    return error.NoTempDirFound;
}
