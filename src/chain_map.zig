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
        /// values.
        pub const InnerMap = M;

        /// A managed map type that takes type `K` for keys and uses `void` as
        /// the value type, and has an `init` method that takes only an
        /// allocator for a parameter.
        pub const KeySet = S;

        /// Type of Slice returned from `keys` function.
        pub const Slice = std.ArrayList(K).Slice;

        allocator: std.mem.Allocator,
        inner_map: InnerMap,
        parent: ?*Self = null,

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

        /// Does up to `n-1` map lookups to determine if key exists in any
        /// parent maps. Failing that, an entry is inserted in this map, never
        /// its parents.
        ///
        /// Thus, this does `n` map lookups in the worst case (the entry is not
        /// found in any ancestor maps and then must be found/inserted into
        /// this map), and 1 map lookup in the best case (the entry exists and
        /// is found in the first ancestor map checked).
        pub fn getOrPut(self: *Self, k: K) !InnerMap.GetOrPutResult {
            var current: ?*Self = self.parent;
            while (current) |c| : (current = c.parent) {
                if (c.inner_map.getEntry(k)) |entry| {
                    return .{
                        .key_ptr = entry.key_ptr,
                        .value_ptr = entry.value_ptr,
                        .found_existing = true,
                    };
                }
            } else {
                return try self.inner_map.getOrPut(k);
            }
        }

        pub fn count(self: *Self) !usize {
            var key_set = try self.keySet(self.allocator);
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
                const cnt = c.inner_map.count();
                try return_set.ensureUnusedCapacity(@intCast(cnt));

                var key_iterator = c.inner_map.keyIterator();
                while (key_iterator.next()) |key| {
                    _ = return_set.getOrPutAssumeCapacity(key.*);
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
        /// of keys other than map encounter order can be guaranteed unless the
        /// type passed in to define `KeySet` has some guaranteed ordering.
        ///
        /// Caller owns the returned slice.
        pub fn keys(self: *Self, alloc: std.mem.Allocator) !Slice {
            var array = std.ArrayList(K).init(alloc);
            defer array.deinit();

            var return_set = KeySet.init(alloc);
            defer return_set.deinit();

            var current: ?*Self = self;
            while (current) |c| : (current = c.parent) {
                const cnt = c.inner_map.count();
                try array.ensureUnusedCapacity(@intCast(cnt));

                var key_iterator = c.inner_map.keyIterator();
                while (key_iterator.next()) |key| {
                    const put_result = try return_set.getOrPut(key.*);
                    if (!put_result.found_existing) {
                        array.appendAssumeCapacity(key.*);
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

    // InnerKeySet.ensureUnusedCapacity(self: *Self, additional_count: Size)
    // InnerKeySet.getOrPutAssumeCapacity(self: *Self, key: K)

    var cm1 = cm_type{
        .allocator = alloc,
        .inner_map = InnerMap.init(alloc),
    };
    defer cm1.deinit();

    try cm1.put("key1", "value1_map1");
    try cm1.put("key2", "value2_map1");

    var cm2 = cm_type{
        .allocator = alloc,
        .inner_map = InnerMap.init(alloc),
        .parent = &cm1,
    };
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

    try std.testing.expectEqual(3, try cm2.count());

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

test "refAllDeclsRecursive" {
    std.testing.refAllDeclsRecursive(@This());
}
