const std = @import("std");

pub fn walkDir(repo_root: std.fs.Dir) !void {
    var fba_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const repo_root_string = try repo_root.realpath(".", &fba_buf);
    std.debug.print("What is the repo root? {s}\n", .{repo_root_string});

    try walkDirInner(repo_root_string, repo_root_string, repo_root);
}

fn walkDirInner(repo_root: []const u8, full_path: []const u8, dir: std.fs.Dir) !void {
    var fba_buf: [std.fs.MAX_PATH_BYTES * 2]u8 = undefined;
    var fba_state = std.heap.FixedBufferAllocator.init(&fba_buf);
    const fba = fba_state.allocator();

    std.debug.print("What is current path? {s}\n", .{full_path});
    const basename = std.fs.path.basename(full_path);
    std.debug.print("What is current path basename? {s}\n", .{basename});

    const relative = try std.fs.path.relative(fba, repo_root, full_path);
    defer fba.free(relative);
    if (relative.len == 0) {
        std.debug.print("Current path is the same as repo root.\n", .{});
    } else {
        std.debug.print("What is current path relative to repo root? {s}\n", .{relative});
    }

    // TODO: add code to parse and utilize .hvrtignore file patterns and skip
    // walking directories that are ignored. This should save lots of time
    // *not* walking directories we don't care about.
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        std.debug.print("Entry info: name: {s}, kind: {}\n", .{ entry.name, entry.kind });

        const child_path = try std.fs.path.join(fba, &[_][]const u8{ full_path, entry.name });
        defer fba.free(child_path);

        switch (entry.kind) {
            .directory => {
                var child_dir = try dir.openDir(entry.name, .{ .iterate = true, .no_follow = true, .access_sub_paths = true });
                defer child_dir.close();
                try walkDirInner(repo_root, child_path, child_dir);
            },
            // Ignore all other types for now
            else => {},
        }
    }
}

test walkDir {
    var tmp_dir = std.testing.tmpDir(.{
        .access_sub_paths = true,
        .iterate = true,
        .no_follow = true,
    });
    defer tmp_dir.cleanup();

    const child_dirs = [_][:0]const u8{ "child1/subchild1", "child2/subchild2", "child3/subchild3", "child3/subchild4" };

    for (child_dirs) |dir_name| {
        try tmp_dir.dir.makePath(dir_name);
        std.debug.print("What is the child dir? {s}\n", .{dir_name});
        // std.debug.print("What is the child dir type? {s}\n", .{@typeName(@TypeOf(dir_name))});
    }

    try walkDir(tmp_dir.dir);
}
