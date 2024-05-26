const std = @import("std");

/// Returns a map type that can take a pointer to a map of its own type as a
/// fallback when a key is not present in the current map. This chain of maps
/// will attempt to check a parent for the value to the requested key until
/// there are no more parents to check (i.e. a `null` parent is encountered).
/// This type does not check for circcular references, so do not make circular
/// references unless you want to get caught in an infinite loop.
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

        /// So long as none of the backing maps in the map chain are modified,
        /// the keys in the returned KeySet should remain valid.
        pub fn keys(self: *Self, alloc: std.mem.Allocator) !KeySet {
            var return_set = KeySet.init(alloc);
            errdefer return_set.deinit();

            var current: ?*Self = self;
            while (current) |c| : (current = c.parent) {
                var iterator = c.inner_map.iterator();
                while (iterator.next()) |entry| {
                    try return_set.put(entry.key_ptr.*, void{});
                }
            }
            return return_set;
        }
    };
}

test ChainMap {
    const alloc = std.testing.allocator;

    // Although BufMap works as an InnerMap type here, the extra copying isn't
    // needed, since we only work with constant strings in this test.
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

    var key_set = try cm2.keys(alloc);
    defer key_set.deinit();

    try std.testing.expectEqual(3, key_set.count());

    var iterator = key_set.keyIterator();
    while (iterator.next()) |k| {
        if (!(std.mem.eql(u8, "key1", k.*) or std.mem.eql(u8, "key2", k.*) or std.mem.eql(u8, "key3", k.*))) {
            std.debug.print("\nkey '{s}' did not match one of the expected keys\n", .{k.*});
            try std.testing.expect(false);
        }
    }
}
