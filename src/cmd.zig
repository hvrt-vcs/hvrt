const std = @import("std");

const parse_args = @import("parse_args.zig");
const init = @import("init.zig").init;
const add = @import("add.zig").add;
const commit = @import("commit.zig").commit;

/// It is the responsibility of the caller of `internalMain` to deallocate and
/// deinit args and alloc, if necessary.
pub fn internalMain(alloc: std.mem.Allocator, args: []const [:0]const u8) !void {
    const parsed_args = try parse_args.parseArgs(alloc, args);
    defer parsed_args.deinit();

    if (args.len > 1) {
        const sub_cmd = args[1];
        const cmd_enum_opt = std.meta.stringToEnum(parse_args.Command, sub_cmd);
        if (cmd_enum_opt) |cmd_enum| {
            const repo_dir = if (args.len > 2) try std.fs.realpathAlloc(alloc, args[2]) else try std.process.getCwdAlloc(alloc);
            defer alloc.free(repo_dir);
            const repo_dirZ = try alloc.dupeZ(u8, repo_dir);
            defer alloc.free(repo_dirZ);

            switch (cmd_enum) {
                .init => {
                    try init(alloc, repo_dirZ);
                },
                .add => {
                    // FIXME: this doesn't work if they don't pass a repo path.
                    // Need to do real args parsing at some point.
                    const files = if (args.len > 3) args[3..] else args[2..];

                    try add(alloc, repo_dirZ, files);
                },
                .commit => {
                    try commit(alloc, repo_dirZ, "Dummy message");
                },
                .mv => {
                    try notImplemented(sub_cmd);
                },
                .cp => {
                    try notImplemented(sub_cmd);
                },
                .rm => {
                    try notImplemented(sub_cmd);
                },
            }
        } else {
            std.log.warn("Unknown sub-command given: {s}\n", .{sub_cmd});
            return error.ArgumentError;
        }
    } else {
        std.log.warn("No sub-command given.\n", .{});
        return error.ArgumentError;
    }
}

fn notImplemented(sub_cmd: []const u8) !void {
    std.log.err("Sub-command not implemented yet: {s}.\n", .{sub_cmd});
    return error.NotImplementedError;
}
