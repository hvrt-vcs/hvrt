const std = @import("std");

const parse_args = @import("parse_args.zig");
const argparse = @import("argparse.zig");
const allyouropt = @import("allyouropt.zig");
const init = @import("init.zig").init;
const add = @import("add.zig").add;
const commit = @import("commit.zig").commit;

/// It is the responsibility of the caller of `internalMain` to deallocate and
/// deinit args and gpa, if necessary.
pub fn internalMain(gpa: std.mem.Allocator, raw_args: []const [:0]const u8) !void {
    const args = try parse_args.Args.parseArgs(gpa, raw_args);
    defer args.deinit();

    const argparser = try argparse.ArgumentParser.init(gpa);
    defer argparser.deinit();

    var opt_iter = allyouropt.OptIterator{
        .args = raw_args,
        .short_flags = &.{},
        .long_flags = &.{},
    };

    while (opt_iter.next()) |o| {
        std.log.debug("What is the next option? {any}", .{o});
    }
    try argparser.parse_args(raw_args, true);

    switch (args.command) {
        .global => {
            try args.command.notImplemented();
        },
        .init => {
            try init(gpa, args.repo_dirZ);
        },
        .add => {
            // FIXME: this doesn't work if a repo path isn't passed.
            // Need to do real args parsing at some point.
            // const files = if (raw_args.len > 3) raw_args[3..] else raw_args[2..];

            try add(gpa, args.repo_dirZ, args.add_files);
        },
        .commit => {
            try commit(gpa, args.repo_dirZ, "Dummy message");
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
