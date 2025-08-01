const std = @import("std");
const builtin = @import("builtin");

var debug_allocator_state = std.heap.DebugAllocator(.{}).init;

/// galloc: the Global Allocator
///
/// This will be set differently depending on how the code is compiled.
pub const galloc: std.mem.Allocator = blk: {
    if (builtin.is_test) {
        break :blk std.testing.allocator;
    } else if (builtin.mode == .Debug) {
        break :blk debug_allocator_state.allocator();
    } else {
        // TODO: replace this with a faster zig native allocator,
        // whenever that comes around.
        break :blk std.heap.c_allocator;
    }
};

/// Must be called at program close to ensure any necessary cleanup happens.
pub fn deinit() void {
    defer if (builtin.mode == .Debug) {
        _ = debug_allocator_state.deinit();
    };
}

/// A C style `malloc` using the galloc Allocator.
///
/// FIXME: since `cFree` isn't implemented properly yet,
/// using this is just a memory leak.
///
/// TODO: add header bytes to keep track of things like allocation length.
/// This is a repeat of what is already happening inside most of the allocators,
/// but since this code doesn't have access to that information,
/// we'll just create it again for our own use.
/// Then we can use it in the other export functions defined in this module.
export fn cMalloc(size: c_int) ?*anyopaque {
    const cast_size: usize = @intCast(size);
    const slice = galloc.alloc(u8, cast_size) catch return null;
    return slice.ptr;
}

/// A C style `free` using the galloc Allocator.
export fn cFree(ptr: ?*anyopaque) void {
    _ = ptr;
    @panic("Not implemented yet");
    // galloc.free(ptr);
}

/// A C style `realloc` using the galloc Allocator.
export fn cRealloc(ptr_opt: ?*anyopaque, size: c_int) ?*anyopaque {
    _ = ptr_opt;
    _ = size;

    // If we return null, then the caller will just call malloc again,
    // copy the bytes,
    // and free the original bytes.
    //
    // It isn't efficient, but it is correct.
    // And that is good enough for now.
    return null;
}

/// A C style function to find out the size of an allocation using the galloc Allocator.
///
/// SQLite wants this. Not sure how to best implement it yet.
export fn cSize(ptr: ?*anyopaque) c_int {
    _ = ptr;
    @panic("Not implemented yet");
}

/// Another thing SQLite wants.
export fn cRoundup(size: c_int) c_int {
    const cpu_align = @alignOf(usize);
    const mod = @mod(size, cpu_align);
    const retval = size + (if (mod != 0) mod else cpu_align);
    return retval;
}
