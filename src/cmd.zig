const std = @import("std");

const parse_args = @import("parse_args.zig");
const allyouropt = @import("allyouropt.zig");
const init = @import("init.zig").init;
const add = @import("add.zig").add;
const commit = @import("commit.zig").commit;

/// It is the responsibility of the caller of `internalMain` to deallocate and
/// deinit args and gpa, if necessary.
pub fn internalMain(gpa: std.mem.Allocator, raw_args: []const [:0]const u8) !void {
    const args = try parse_args.Args.parseArgs(gpa, raw_args);
    defer args.deinit();

    switch (args.command) {
        .global => {
            try args.command.notImplemented();
        },
        .init => {
            try init(gpa, (args.gpopts.work_tree orelse "."));
        },
        .add => {
            // FIXME: this doesn't work if a repo path isn't passed.
            // Need to do real args parsing at some point.
            // const files = if (raw_args.len > 3) raw_args[3..] else raw_args[2..];

            try add(gpa, (args.gpopts.work_tree orelse "."), args.add_files);
        },
        .commit => {
            try commit(gpa, (args.gpopts.work_tree orelse "."), "Dummy message");
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
