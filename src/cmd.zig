const std = @import("std");

const parse_args = @import("parse_args.zig");
const Config = @import("config.zig").Config;
const init = @import("init.zig").init;
const add = @import("add.zig").add;
const commit = @import("commit.zig").commit;

/// It is the responsibility of the caller of `internalMain` to deallocate and
/// deinit args and gpa, if necessary.
pub fn internalMain(gpa: std.mem.Allocator, raw_args: []const [:0]const u8) !void {
    const args = try parse_args.Args.parseArgs(gpa, raw_args);
    defer args.deinit();
    const arena = args.arena_ptr.allocator();

    const wt_first = args.gpopts.get_work_tree();
    const wt_final = args.gpopts.find_work_tree_root(arena) catch wt_first;
    const config_path = try std.fs.path.join(gpa, &.{ wt_final, ".hvrt", "config.voll" });
    defer gpa.free(config_path);

    const config_string_opt: ?[]const u8 = blk: {
        var config_file = std.fs.openFileAbsolute(config_path, .{}) catch {
            break :blk null;
        };
        defer config_file.close();

        break :blk config_file.readToEndAlloc(gpa, std.math.maxInt(usize)) catch null;
    };
    defer if (config_string_opt) |config_string| gpa.free(config_string);

    // Real user configs will have typos.
    // Be kind and skip bad lines.
    // Parse out what we can.
    // The parser will still print warnings for bad lines.
    var parsed_config = try Config.init(
        gpa,
        config_string_opt orelse &.{},
        .{ .skip_bad_lines = true },
    );
    defer parsed_config.deinit();

    switch (args.command) {
        .global => {
            try args.command.notImplemented();
        },
        .init => {
            try init(gpa, wt_first);
        },
        .add => {
            try add(
                gpa,
                parsed_config,
                wt_final,
                args.trailing_args,
            );
        },
        .commit => |commit_opts| {
            try commit(
                gpa,
                wt_final,
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
