const std = @import("std");

const init = @import("init.zig");
const add = @import("add.zig");

/// It is the responsibility of the caller of `internalMain` to deallocate and
/// deinit args and alloc, if necessary.
pub fn internalMain(alloc: std.mem.Allocator, args: []const [:0]const u8) !void {
    if (args.len > 1) {
        const sub_cmd = args[1];
        const repo_dir = if (args.len > 2) try std.fs.realpathAlloc(alloc, args[2]) else try std.process.getCwdAlloc(alloc);
        defer alloc.free(repo_dir);
        const repo_dirZ = try alloc.dupeZ(u8, repo_dir);
        defer alloc.free(repo_dirZ);

        if (std.mem.eql(u8, sub_cmd, "init")) {
            try init.init(alloc, repo_dirZ);
        } else if (std.mem.eql(u8, sub_cmd, "add")) {
            // FIXME: this doesn't work if they don't pass a repo path. Need to
            // do args parsing at some point.
            const files = if (args.len > 3) args[3..] else args[2..];

            try add.add(alloc, repo_dirZ, files);
        } else if (std.mem.eql(u8, sub_cmd, "commit")) {
            try notImplemented(sub_cmd);
        } else if (std.mem.eql(u8, sub_cmd, "mv")) {
            try notImplemented(sub_cmd);
        } else if (std.mem.eql(u8, sub_cmd, "cp")) {
            try notImplemented(sub_cmd);
        } else if (std.mem.eql(u8, sub_cmd, "rm")) {
            try notImplemented(sub_cmd);
        } else {
            std.log.err("Unknown sub-command given: {s}.\n", .{sub_cmd});
            return error.ArgumentError;
        }
    } else {
        std.log.err("No sub-command given.\n", .{});
        return error.ArgumentError;
    }
}

fn notImplemented(sub_cmd: []const u8) !void {
    std.log.err("Sub-command not implemented yet: {s}.\n", .{sub_cmd});
    return error.NotImplementedError;
}
