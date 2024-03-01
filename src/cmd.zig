const std = @import("std");

const init = @import("init.zig");

/// It is the responsibility of the caller of `internalMain` to deallocate and
/// deinit args and alloc, if necessary.
pub fn internalMain(alloc: std.mem.Allocator, args: []const [:0]const u8) !void {
    if (args.len > 1) {
        const sub_cmd = args[1];
        if (std.mem.eql(u8, sub_cmd, "init")) {
            const repo_dir = if (args.len > 2) try std.fs.realpathAlloc(alloc, args[2]) else try std.process.getCwdAlloc(alloc);
            defer alloc.free(repo_dir);

            try init.init(alloc, repo_dir);
        } else if (std.mem.eql(u8, sub_cmd, "add")) {
            try notImplemented(sub_cmd);
        } else if (std.mem.eql(u8, sub_cmd, "commit")) {
            try notImplemented(sub_cmd);
        } else if (std.mem.eql(u8, sub_cmd, "mv")) {
            try notImplemented(sub_cmd);
        } else if (std.mem.eql(u8, sub_cmd, "cp")) {
            try notImplemented(sub_cmd);
        } else if (std.mem.eql(u8, sub_cmd, "rm")) {
            try notImplemented(sub_cmd);
        } else {
            std.debug.print("Unknown sub-command given: {s}.\n", .{sub_cmd});
            return error.ArgumentError;
        }
    } else {
        std.debug.print("No sub-command given.\n", .{});
        return error.ArgumentError;
    }
}

fn notImplemented(sub_cmd: []const u8) !void {
    std.debug.print("Sub-command not implemented yet: {s}.\n", .{sub_cmd});
    return error.NotImplementedError;
}
