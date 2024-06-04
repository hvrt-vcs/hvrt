const std = @import("std");

pub const IgnorePattern = struct {
    ignore_root: []const u8,
    original_pattern: []const u8,
    pattern: []const u8,
    as_dir: bool,
    rooted: bool,
    negated: bool,

    pub fn deinit(self: IgnorePattern) void {
        _ = self; // autofix
    }

    /// For gitignore matching rules see URL: https://git-scm.com/docs/gitignore
    ///
    /// `ignore_file_path` is assumed to be relative from the root of the
    /// worktree. If it isn't, pattern matching relative to the "current
    /// directory" will not work correctly.
    pub fn parseIgnoreFile(arena: std.mem.Allocator, ignore_file_path: []const u8, ignore_file_reader: anytype, max_read_size: usize) ![]IgnorePattern {
        if (std.fs.path.isAbsolute(ignore_file_path)) return error.IgnoreFileIsAbsolute;

        const whole_file = try ignore_file_reader.readAllAlloc(arena, max_read_size);
        var tokenizer = std.mem.tokenizeAny(u8, whole_file, "\r\n");

        var line_cnt: usize = 0;
        while (tokenizer.next()) |_| {
            line_cnt += 1;
        }
        tokenizer.reset();

        // is `null` if there is no parent directory.
        const ignore_root = std.fs.path.dirname(ignore_file_path) orelse ".";

        var array = std.ArrayList(IgnorePattern).init(arena);

        // Add one to line_cnt in case there is no trailing newline in file.
        try array.ensureTotalCapacity(line_cnt + 1);

        while (tokenizer.next()) |original_text| {
            var cur_pat: IgnorePattern = .{
                .ignore_root = ignore_root,
                .original_pattern = original_text,
                .pattern = std.mem.trimRight(u8, original_text, " \t\n\r"),
                .as_dir = false,
                .rooted = false,
                .negated = false,
            };

            // Ignore empty or commented lines
            if (cur_pat.pattern.len == 0 or std.mem.startsWith(u8, cur_pat.pattern, "#")) {
                continue;
            }

            // If there is an escape character at the end, the whitespace needs to be preserved
            if (std.mem.endsWith(u8, cur_pat.pattern, "\\") and cur_pat.pattern.len < original_text.len) {
                cur_pat.pattern = original_text[0 .. cur_pat.pattern.len + 1];
            }

            // There is a slash in the path somewhere other than the end
            if (std.mem.indexOfScalar(u8, std.mem.trimRight(u8, cur_pat.pattern, "/"), '/') != null) {
                cur_pat.rooted = true;
                cur_pat.pattern = std.mem.trimLeft(u8, cur_pat.pattern, "/");
            }

            if (std.mem.endsWith(u8, cur_pat.pattern, "/")) {
                cur_pat.as_dir = true;
                cur_pat.pattern = std.mem.trimRight(u8, cur_pat.pattern, "/");
            }

            if (std.mem.startsWith(u8, cur_pat.pattern, "!")) {
                cur_pat.negated = true;
                cur_pat.pattern = std.mem.trimLeft(u8, cur_pat.pattern, "!");
            }

            array.appendAssumeCapacity(cur_pat);
        }

        return try array.toOwnedSlice();
    }
};

test "IgnorePattern.parseIgnoreFile" {
    const alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    const contents =
        \\# a comment line
        \\# a blank line below
        \\
        \\pattern1
        \\/child3/**
        \\!child3/subchild4
        \\child2/
        \\
    ;

    var fbs = std.io.fixedBufferStream(contents);

    const patterns = try IgnorePattern.parseIgnoreFile(arena.allocator(), ".hvrtignore", fbs.reader(), contents.len);

    try std.testing.expectEqual(4, patterns.len);

    try std.testing.expectEqual(false, patterns[0].rooted);
    try std.testing.expectEqual(null, std.mem.indexOfScalar(u8, patterns[0].original_pattern, '/'));
    try std.testing.expectEqual(null, std.mem.indexOfScalar(u8, patterns[0].pattern, '/'));

    try std.testing.expectEqual(true, patterns[1].rooted);
    try std.testing.expectEqual(0, std.mem.indexOfScalar(u8, patterns[1].original_pattern, '/'));
    try std.testing.expectEqual(6, std.mem.indexOfScalar(u8, patterns[1].pattern, '/'));

    try std.testing.expectEqual(false, patterns[1].negated);
    try std.testing.expectEqual(null, std.mem.indexOfScalar(u8, patterns[1].original_pattern, '!'));
    try std.testing.expectEqual(null, std.mem.indexOfScalar(u8, patterns[1].pattern, '!'));

    try std.testing.expectEqual(true, patterns[2].negated);
    try std.testing.expectEqual(0, std.mem.indexOfScalar(u8, patterns[2].original_pattern, '!'));
    try std.testing.expectEqual(null, std.mem.indexOfScalar(u8, patterns[2].pattern, '!'));

    try std.testing.expectEqual(false, patterns[0].as_dir);
    try std.testing.expectEqual(null, std.mem.indexOfScalar(u8, patterns[0].original_pattern, '/'));
    try std.testing.expectEqual(null, std.mem.indexOfScalar(u8, patterns[0].pattern, '/'));

    try std.testing.expectEqual(true, patterns[3].as_dir);
    try std.testing.expectEqual(6, std.mem.indexOfScalar(u8, patterns[3].original_pattern, '/'));
    try std.testing.expectEqual(null, std.mem.indexOfScalar(u8, patterns[3].pattern, '/'));
}

pub fn DirWalker(
    comptime Ctx: type,
    comptime visit: fn (context: *Ctx, repo_root: std.fs.Dir, relpath: []const u8) void,
    comptime ignore: fn (context: *Ctx, repo_root: std.fs.Dir, relpath: []const u8) void,
) type {
    return struct {
        pub const Self = @This();
        context: *Ctx,
        repo_root: std.fs.Dir,

        const visit_fn = visit;
        const ignore_fn = ignore;

        pub fn init(repo_root: std.fs.Dir, context: *Ctx) Self {
            return .{ .repo_root = repo_root, .context = context };
        }

        pub fn walkDir(self: *Self, gpa: std.mem.Allocator, repo_root: std.fs.Dir) !void {
            var fba_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
            const repo_root_string = try repo_root.realpath(".", &fba_buf);
            std.debug.print("What is the repo root? {s}\n", .{repo_root_string});

            try self.walkDirInner(gpa, repo_root_string, repo_root_string, repo_root);
        }

        fn walkDirInner(self: *Self, gpa: std.mem.Allocator, repo_root: []const u8, full_path: []const u8, dir: std.fs.Dir) !void {
            std.debug.print("What is current path? {s}\n", .{full_path});
            const basename = std.fs.path.basename(full_path);
            std.debug.print("What is current path basename? {s}\n", .{basename});

            const relative = try std.fs.path.relative(gpa, repo_root, full_path);
            defer gpa.free(relative);
            if (relative.len == 0) {
                std.debug.print("Current path is the same as repo root.\n", .{});
            } else {
                std.debug.print("What is current path relative to repo root? {s}\n", .{relative});
            }

            // TODO: add code to parse and utilize .hvrtignore file patterns and skip
            // walking directories that are ignored. This should save lots of time
            // *not* walking directories we don't care about.

            const ignore_file_path = if (relative.len == 0) ".hvrtignore" else try std.fs.path.join(gpa, &[_][]const u8{ relative, ".hvrtignore" });
            defer if (relative.len != 0) gpa.free(ignore_file_path);

            var arena = std.heap.ArenaAllocator.init(gpa);
            defer arena.deinit();

            const ignore_patterns = blk: {
                const fallback: []IgnorePattern = &.{};

                var file = dir.openFile(".hvrtignore", .{}) catch break :blk fallback;
                defer file.close();
                const fstat = file.stat() catch break :blk fallback;
                break :blk IgnorePattern.parseIgnoreFile(arena.allocator(), ignore_file_path, file.reader(), fstat.size) catch fallback;
            };
            _ = ignore_patterns; // autofix

            var iter = dir.iterate();
            while (try iter.next()) |entry| {
                std.debug.print("Entry info: name: {s}, kind: {}\n", .{ entry.name, entry.kind });

                const child_path = try std.fs.path.join(gpa, &[_][]const u8{ full_path, entry.name });
                defer gpa.free(child_path);

                switch (entry.kind) {
                    .directory => {
                        var child_dir = try dir.openDir(entry.name, .{ .iterate = true, .no_follow = true, .access_sub_paths = true });
                        defer child_dir.close();
                        try self.walkDirInner(gpa, repo_root, child_path, child_dir);
                    },
                    // Ignore all other types for now
                    else => {},
                }
            }
        }
    };
}

fn dummy(context: *anyopaque, repo_root: std.fs.Dir, relpath: []const u8) void {
    _ = context; // autofix
    _ = repo_root; // autofix
    _ = relpath; // autofix
}

test "DirWalker.walkDir" {
    const alloc = std.testing.allocator;
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

    const ctype = DirWalker(anyopaque, dummy, dummy);

    var dw = ctype.init(tmp_dir.dir, undefined);
    _ = &dw; // autofix

    try dw.walkDir(alloc, tmp_dir.dir);
}
