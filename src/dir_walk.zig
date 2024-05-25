const std = @import("std");

pub fn ChainMap(comptime K: type, comptime V: type) type {
    return struct {
        pub const Self = @This();
        pub const Map = std.AutoHashMap(K, V);

        map: Map,
        parent: ?*Self = null,

        pub fn init(allocator: std.mem.Allocator, parent: ?*Self) Self {
            return .{
                .map = Map.init(allocator),
                .parent = parent,
            };
        }

        pub fn deinit(self: *Self) void {
            self.map.deinit();
        }

        pub fn get(self: Self, k: K) ?V {
            if (self.map.get(k)) |v| {
                return v;
            } else if (self.parent) |parent| {
                return parent.get(k);
            } else {
                return null;
            }
        }

        pub fn put(self: Self, k: K, v: V) !void {
            try self.map.put(k, v);
        }

        pub fn getOrPut(self: Self, k: K, v: V) !Map.GetOrPutResult {
            return try self.map.getOrPut(k, v);
        }
    };
}
