const std = @import("std");
const config = @import("config.zig");

/// It is the responsibility of the caller of `status` to deallocate and
/// deinit `gpa`, `repo_path`, and `files`, if necessary.
pub fn status(gpa: std.mem.Allocator, cfg: config.Config, repo_path: []const u8, files: []const []const u8) !void {
    return error.NotImplemented;
}
