const std = @import("std");

/// Returns a map type that can take a pointer to a map of its own type as a
/// fallback when a key is not present in the current map. This chain of maps
/// will attempt to check a parent for the value to the requested key until
/// there are no more parents to check (i.e. a `null` parent is encountered).
///
/// This type does not check for circular references, so you should not make
/// circular references with parents unless you want to get caught in an
/// infinite loop.
pub fn ChainMap(comptime K: type, comptime V: type, comptime M: type, comptime S: type) type {
    return struct {
        pub const Self = @This();

        /// A managed map type that takes type `K` for keys and type `V` for
        /// values, and has an `init` method that takes only an allocator for a
        /// parameter.
        pub const InnerMap = M;

        /// A managed map type that takes type `K` for keys and uses `void` as
        /// the value type, and has an `init` method that takes only an
        /// allocator for a parameter.
        pub const KeySet = S;

        /// Type of Slice returned from `keys` function.
        pub const Slice = std.ArrayList(K).Slice;

        inner_map: InnerMap,
        parent: ?*Self = null,

        pub fn init(allocator: std.mem.Allocator, parent: ?*Self) Self {
            return .{
                .inner_map = InnerMap.init(allocator),
                .parent = parent,
            };
        }

        pub fn deinit(self: *Self) void {
            self.inner_map.deinit();
        }

        pub fn get(self: *Self, k: K) ?V {
            var current: ?*Self = self;
            return while (current) |c| : (current = c.parent) {
                if (c.inner_map.get(k)) |v| {
                    break v;
                }
            } else null;
        }

        pub fn put(self: *Self, k: K, v: V) !void {
            try self.inner_map.put(k, v);
        }

        pub fn getOrPut(self: *Self, k: K, v: V) !InnerMap.GetOrPutResult {
            return try self.inner_map.getOrPut(k, v);
        }

        /// FIXME: don't require an allocator to count keys. Maybe use the one
        /// from `init` or something.
        pub fn count(self: *Self, alloc: std.mem.Allocator) !usize {
            var key_set = try self.keySet(alloc);
            defer key_set.deinit();

            return key_set.count();
        }

        /// So long as none of the backing maps in the map chain are modified,
        /// the keys in the returned KeySet should remain valid.
        pub fn keySet(self: *Self, alloc: std.mem.Allocator) !KeySet {
            var return_set = KeySet.init(alloc);
            errdefer return_set.deinit();

            var current: ?*Self = self;
            while (current) |c| : (current = c.parent) {
                var iterator = c.inner_map.iterator();
                while (iterator.next()) |entry| {
                    _ = try return_set.getOrPut(entry.key_ptr.*);
                }
            }
            return return_set;
        }

        /// So long as none of the backing maps in the map chain are modified,
        /// the keys in the returned Slice should remain valid.
        ///
        /// Keys are ordered by encounter order. In essence, the keys from the
        /// current map are returned, then any keys in the parent map not
        /// previously encountered in the current map are returned, and so on
        /// and so forth until all keys from all maps in the chain have been
        /// encountered. This can be thought of as a union of all keys in all
        /// maps in the chain, in encounter order.
        ///
        /// Because of the pseudo-random nature of hash maps, no other ordering
        /// of keys other than map encounter order can be guaranteed.
        pub fn keys(self: *Self, alloc: std.mem.Allocator) !Slice {
            var array = std.ArrayList(K).init(alloc);
            defer array.deinit();

            var return_set = KeySet.init(alloc);
            defer return_set.deinit();

            var current: ?*Self = self;
            while (current) |c| : (current = c.parent) {
                var iterator = c.inner_map.iterator();
                while (iterator.next()) |entry| {
                    const put_result = try return_set.getOrPut(entry.key_ptr.*);
                    if (!put_result.found_existing) {
                        try array.append(entry.key_ptr.*);
                    }
                }
            }

            return try array.toOwnedSlice();
        }
    };
}

test ChainMap {
    const alloc = std.testing.allocator;

    // Although BufMap works as an InnerMap type here, the extra copying isn't
    // needed, since we only work with constant string literals in this test.
    // const InnerMap = std.BufMap;

    const InnerMap = std.StringHashMap([]const u8);
    const InnerKeySet = std.StringHashMap(void);
    const cm_type = ChainMap([]const u8, []const u8, InnerMap, InnerKeySet);

    var cm1 = cm_type.init(alloc, null);
    defer cm1.deinit();

    try cm1.put("key1", "value1_map1");
    try cm1.put("key2", "value2_map1");

    var cm2 = cm_type.init(alloc, &cm1);
    defer cm2.deinit();

    try cm2.put("key2", "value2_map2");
    try cm2.put("key3", "value3_map2");

    // Overrides on a more recent map should be found first
    const expected1 = "value2_map2";
    const actual1 = cm2.get("key2") orelse "";

    try std.testing.expectEqualStrings(expected1, actual1);

    // keys not found in the most recent map should attempt to be found in prior maps
    const expected2 = "value1_map1";
    const actual2 = cm2.get("key1") orelse "";

    try std.testing.expectEqualStrings(expected2, actual2);

    // Nonexistent keys should return `null`;
    const actual3 = cm2.get("key4");
    try std.testing.expectEqual(null, actual3);

    try std.testing.expectEqual(3, try cm2.count(alloc));

    const key_slice = try cm2.keys(alloc);
    defer alloc.free(key_slice);

    try std.testing.expectEqual(3, key_slice.len);

    for (key_slice) |k| {
        if (!(std.mem.eql(u8, "key1", k) or std.mem.eql(u8, "key2", k) or std.mem.eql(u8, "key3", k))) {
            std.debug.print("\nkey '{s}' did not match one of the expected keys\n", .{k});
            try std.testing.expect(false);
        }
    }
}

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
