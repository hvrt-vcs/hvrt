const std = @import("std");

pub const Args = struct {
    alloc: std.mem.Allocator,
    arena_ptr: *std.heap.ArenaAllocator,

    pub fn deinit(self: Args) void {
        self.arena_ptr.deinit();
        self.alloc.destroy(self.arena_ptr);
    }
};

// Caller must call `deinit` on returned `Args` object when it is no longer
// needed, otherwise memory will be leaked.
pub fn parseArgs(alloc: std.mem.Allocator, args: []const [:0]const u8) !Args {
    _ = args;
    const arena_ptr = try alloc.create(std.heap.ArenaAllocator);
    arena_ptr.* = std.heap.ArenaAllocator.init(alloc);

    return Args{
        .alloc = alloc,
        .arena_ptr = arena_ptr,
    };
}
