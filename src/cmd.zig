const std = @import("std");

const parse_args = @import("parse_args.zig");
const allyouropt = @import("allyouropt.zig");
const config = @import("config.zig");
const init = @import("init.zig").init;
const add = @import("add.zig").add;
const commit = @import("commit.zig").commit;

/// It is the responsibility of the caller of `internalMain` to deallocate and
/// deinit args and gpa, if necessary.
pub fn internalMain(gpa: std.mem.Allocator, raw_args: []const [:0]const u8) !void {
    const args = try parse_args.Args.parseArgs(gpa, raw_args);
    defer args.deinit();

    const wt = args.gpopts.get_work_tree();
    const config_path = try std.fs.path.join(gpa, &.{ wt, ".hvrt", "config.voll" });
    defer gpa.free(config_path);

    const config_string = blk: {
        var config_file = std.fs.openFileAbsolute(config_path, .{}) catch {
            break :blk &.{};
        };
        defer config_file.close();

        break :blk config_file.readToEndAlloc(gpa, std.math.maxInt(usize)) catch &.{};
    };
    defer if (config_string.len != 0) gpa.free(config_string);

    var parsed_config = try config.Config.parse(gpa, config_string);
    defer parsed_config.deinit();

    switch (args.command) {
        .global => {
            try args.command.notImplemented();
        },
        .init => {
            try init(gpa, args.gpopts.get_work_tree());
        },
        .add => {
            try add(gpa, args.gpopts.get_work_tree(), args.trailing_args);
        },
        .commit => |commit_opts| {
            try commit(
                gpa,
                args.gpopts.get_work_tree(),
                try commit_opts.get_message(),
            );
        },
        .mv => {
            try args.command.notImplemented();
        },
        .cp => {
            try args.command.notImplemented();
        },
        .rm => {
            try args.command.notImplemented();
        },
    }
}

test "refAllDeclsRecursive" {
    std.testing.refAllDeclsRecursive(@This());
}
