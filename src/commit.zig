const std = @import("std");

/// It is the responsibility of the caller of `commit` to deallocate and
/// deinit alloc, repo_path, and files, if necessary.
pub fn commit(alloc: std.mem.Allocator, repo_path: [:0]const u8, message: [:0]const u8) !void {
    _ = message;
    _ = repo_path;
    _ = alloc;

    return error.NotImplementedError;
}
