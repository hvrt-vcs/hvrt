const std = @import("std");

const log = std.log.scoped(.dir_walker);

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
    pub fn parseIgnoreFile(arena: std.mem.Allocator, ignore_file_path: []const u8, ignore_file_contents: []const u8) ![]IgnorePattern {
        if (std.fs.path.isAbsolute(ignore_file_path)) return error.IgnoreFileIsAbsolute;

        // is `null` if there is no parent directory.
        const ignore_root = std.fs.path.dirname(ignore_file_path) orelse ".";

        var array = std.ArrayList(IgnorePattern).init(arena);
        defer array.deinit();

        var tokenizer = std.mem.tokenizeAny(u8, ignore_file_contents, "\r\n");

        // Add one to line_cnt in case there is no trailing newline on last
        // line of file.
        var line_cnt: usize = 1;
        while (tokenizer.next()) |_| : (line_cnt += 1) {}
        tokenizer.reset();

        try array.ensureTotalCapacity(line_cnt);

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

    const patterns = try IgnorePattern.parseIgnoreFile(arena.allocator(), ".hvrtignore", contents);

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

pub const FileIgnorer = struct {
    context: *anyopaque,
    vtable: VTable,

    pub const VTable = struct {
        put_patterns: *const fn (context: *anyopaque, relpath: []const u8, patterns: []IgnorePattern) anyerror!void,
        remove_patterns: *const fn (context: *anyopaque, relpath: []const u8) void,
        is_ignored: *const fn (context: *anyopaque, relpath: []const u8) bool,
    };

    pub inline fn put_patterns(self: FileIgnorer, relpath: []const u8, patterns: []IgnorePattern) !void {
        return self.vtable.put_patterns(self.context, relpath, patterns);
    }

    pub inline fn remove_patterns(self: FileIgnorer, relpath: []const u8) void {
        self.vtable.remove_patterns(self.context, relpath);
    }

    pub inline fn is_ignored(self: FileIgnorer, relpath: []const u8) bool {
        return self.vtable.is_ignored(self.context, relpath);
    }
};

/// A `FileIgnorer` that takes another file ignorer and inverts its result.
///
/// Thus, what was ignored in the child `FileIgnorer` is not ignored in the
/// parent, and what was not ignored in the child is now ignored in the parent.
pub const FileIgnorerInverter = struct {
    file_ignorer: FileIgnorer,

    pub fn fileIgnorer(self: *FileIgnorerInverter) FileIgnorer {
        return .{
            .context = @ptrCast(self),
            .vtable = .{
                .put_patterns = put_patterns,
                .remove_patterns = remove_patterns,
                .is_ignored = is_ignored,
            },
        };
    }

    /// Straight pass through to the internal `file_ignorer`.
    pub fn put_patterns(context: *anyopaque, relpath: []const u8, patterns: []IgnorePattern) anyerror!void {
        const self = @as(*FileIgnorerInverter, @ptrCast(context));
        try self.file_ignorer.put_patterns(relpath, patterns);
    }

    /// Straight pass through to the internal `file_ignorer`.
    pub fn remove_patterns(context: *anyopaque, relpath: []const u8) void {
        const self = @as(*FileIgnorerInverter, @ptrCast(context));
        self.file_ignorer.remove_patterns(relpath);
    }

    /// Returns the opposite of what the internal `file_ignorer` returns.
    pub fn is_ignored(context: *anyopaque, relpath: []const u8) bool {
        const self = @as(*FileIgnorerInverter, @ptrCast(context));
        return !self.file_ignorer.is_ignored(relpath);
    }
};

/// A `FileIgnorer` that chains multiple ignorers together.
pub const ChainedFileIgnorer = struct {
    file_ignorers: []FileIgnorer,

    pub fn fileIgnorer(self: *ChainedFileIgnorer) FileIgnorer {
        return .{
            .context = @ptrCast(self),
            .vtable = .{
                .put_patterns = put_patterns,
                .remove_patterns = remove_patterns,
                .is_ignored = is_ignored,
            },
        };
    }

    /// Only put patterns on first (i.e. "zeroeth") internal file ignorer, or
    /// does nothing if internal `file_ignorers` slice is empty.
    pub fn put_patterns(context: *anyopaque, relpath: []const u8, patterns: []IgnorePattern) anyerror!void {
        const self = @as(*ChainedFileIgnorer, @ptrCast(context));
        if (self.file_ignorers.len != 0) {
            try self.file_ignorers[0].put_patterns(relpath, patterns);
        }
    }

    /// Only remove patterns from first (i.e. "zeroeth") internal file ignorer,
    /// or does nothing if internal `file_ignorers` slice is empty.
    pub fn remove_patterns(context: *anyopaque, relpath: []const u8) void {
        const self = @as(*ChainedFileIgnorer, @ptrCast(context));
        if (self.file_ignorers.len != 0) {
            self.file_ignorers[0].remove_patterns(relpath);
        }
    }

    /// Checks all internal file ignorers in order until one returns `true`,
    /// otherwise returns `false`.
    pub fn is_ignored(context: *anyopaque, relpath: []const u8) bool {
        const self = @as(*ChainedFileIgnorer, @ptrCast(context));
        for (self.file_ignorers) |file_ignorer| {
            if (file_ignorer.is_ignored(relpath)) return true;
        } else return false;
    }
};

test {
    _ = FileIgnorerInverter;
    _ = ChainedFileIgnorer;
}

fn noop_put_patterns(context: *anyopaque, relpath: []const u8, patterns: []IgnorePattern) !void {
    _ = context;
    _ = relpath;
    _ = patterns;
}

fn noop_remove_patterns(context: *anyopaque, relpath: []const u8) void {
    _ = context;
    _ = relpath;
}

fn noop_is_ignored(context: *anyopaque, relpath: []const u8) bool {
    _ = context;
    _ = relpath;
    return false;
}

/// An ignorer instance that ignores putting and removing patterns and that
/// never ignores any file paths.
pub const noop_ignorer: FileIgnorer = .{
    .context = undefined,
    .vtable = .{
        .put_patterns = noop_put_patterns,
        .remove_patterns = noop_remove_patterns,
        .is_ignored = noop_is_ignored,
    },
};

pub fn DirWalker(
    comptime Context: type,
    comptime visit: fn (context: Context, relpath: []const u8) void,
) type {
    return struct {
        pub const Self = @This();

        context: Context,
        file_ignorer: FileIgnorer,
        repo_root: std.fs.Dir,

        pub const visit_fn = visit;

        pub const IgnoreCache = std.StringHashMap([]IgnorePattern);

        pub fn init(repo_root: std.fs.Dir, context: Context, file_ignorer: FileIgnorer) Self {
            return .{
                .context = context,
                .file_ignorer = file_ignorer,
                .repo_root = repo_root,
            };
        }

        pub fn walkDir(self: *Self, gpa: std.mem.Allocator, start_path: ?[]const u8) !void {
            var fba_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
            const repo_root_string = try self.repo_root.realpath(".", &fba_buf);
            log.debug("What is the repo root? {s}\n", .{repo_root_string});

            var ignore_cache = IgnoreCache.init(gpa);
            defer ignore_cache.deinit();

            try self.walkDirInner(
                gpa,
                &ignore_cache,
                repo_root_string,
                start_path orelse repo_root_string,
                self.repo_root,
            );
        }

        fn walkDirInner(self: *Self, gpa: std.mem.Allocator, ignore_cache: *IgnoreCache, repo_root: []const u8, full_path: []const u8, dir: std.fs.Dir) !void {
            log.debug("What is current path? {s}\n", .{full_path});
            const basename = std.fs.path.basename(full_path);
            log.debug("What is current path basename? {s}\n", .{basename});

            const relative = try std.fs.path.relative(gpa, repo_root, full_path);
            defer gpa.free(relative);
            if (relative.len == 0) {
                log.debug("Current path is the same as repo root.\n", .{});
            } else {
                log.debug("What is current path relative to repo root? {s}\n", .{relative});
            }

            // TODO: add code to parse and utilize .hvrtignore file patterns and skip
            // walking directories that are ignored. This should save lots of time
            // *not* walking directories we don't care about.

            const ignore_file_path = if (relative.len == 0) ".hvrtignore" else try std.fs.path.join(gpa, &[_][]const u8{ relative, ".hvrtignore" });
            defer if (relative.len != 0) gpa.free(ignore_file_path);

            var arena = std.heap.ArenaAllocator.init(gpa);
            defer arena.deinit();

            var contents: []const u8 = &.{};
            const ignore_patterns = blk: {
                const fallback: []IgnorePattern = &.{};

                var file = dir.openFile(".hvrtignore", .{}) catch break :blk fallback;
                defer file.close();

                const fstat = file.stat() catch break :blk fallback;

                contents = file.readToEndAllocOptions(arena.allocator(), fstat.size, fstat.size, @alignOf(u8), null) catch break :blk fallback;
                break :blk IgnorePattern.parseIgnoreFile(arena.allocator(), ignore_file_path, contents) catch fallback;
            };
            try ignore_cache.put(relative, ignore_patterns);
            defer _ = ignore_cache.remove(relative);

            try self.file_ignorer.put_patterns(relative, ignore_patterns);
            defer self.file_ignorer.remove_patterns(relative);

            var iter = dir.iterate();
            while (try iter.next()) |entry| {
                log.debug("Entry info: name: {s}, kind: {}\n", .{ entry.name, entry.kind });

                const child_path = try std.fs.path.join(gpa, &[_][]const u8{ full_path, entry.name });
                defer gpa.free(child_path);

                const relative_child_path = try std.fs.path.relative(gpa, repo_root, child_path);
                defer gpa.free(relative_child_path);

                if (self.file_ignorer.is_ignored(relative_child_path)) continue;

                switch (entry.kind) {
                    .directory => {
                        var child_dir = try dir.openDir(entry.name, .{ .iterate = true, .no_follow = true, .access_sub_paths = true });
                        defer child_dir.close();
                        try self.walkDirInner(gpa, ignore_cache, repo_root, child_path, child_dir);
                    },
                    else => visit_fn(self.context, relative_child_path),
                }
            }
        }
    };
}

fn dummy(context: *anyopaque, relpath: []const u8) void {
    _ = context; // autofix
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
        log.debug("What is the child dir? {s}\n", .{dir_name});
        log.debug("What is the child dir type? {s}\n", .{@typeName(@TypeOf(dir_name))});
    }

    const ctype = DirWalker(*anyopaque, dummy);

    var dw = ctype.init(tmp_dir.dir, undefined, noop_ignorer);
    _ = &dw; // autofix

    try dw.walkDir(alloc, null);
}
