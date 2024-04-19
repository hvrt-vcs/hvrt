const std = @import("std");

pub const Command = enum {
    add,
    commit,
    cp,
    init,
    mv,
    rm,
};

pub const Args = struct {
    alloc: std.mem.Allocator,
    arena_ptr: *std.heap.ArenaAllocator,

    command: Command,

    pub fn deinit(self: Args) void {
        self.arena_ptr.deinit();
        self.alloc.destroy(self.arena_ptr);
    }
};

// Caller must call `deinit` on returned `Args` object when it is no longer
// needed, otherwise memory will be leaked.
pub fn parseArgs(alloc: std.mem.Allocator, args: []const [:0]const u8) !Args {
    const arena_ptr = try alloc.create(std.heap.ArenaAllocator);
    arena_ptr.* = std.heap.ArenaAllocator.init(alloc);

    for (args[1..], 1..) |arg, i| {
        _ = arg;
        _ = i;
    }

    // FIXME: actually parse this from somewhere
    const cmd = .init;

    return Args{
        .alloc = alloc,
        .arena_ptr = arena_ptr,
        .command = cmd,
    };
}
