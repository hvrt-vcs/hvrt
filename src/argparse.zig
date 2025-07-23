// This module is somewhat modelled on the Python argparse module.
// See: https://docs.python.org/3/library/argparse.html
const std = @import("std");
const c = @import("c.zig");

const SubParserHashMap = std.array_hash_map.StringArrayHashMap(*ArgumentParser);

const log = std.log.scoped(.argparse);

pub const ArgumentAction = enum {
    store,
    store_const,
    store_true,
    store_false,
    append,
    append_const,
    // extend,
    count,
    help,
    version,
};

// pub const ArgumentNargs = enum {};

const Argument = struct {
    // For reference from Python argparse docs:
    //
    // name or flags - Either a name or a list of option strings, e.g. 'foo' or '-f', '--foo'.
    // action - The basic type of action to be taken when this argument is encountered at the command line.
    // nargs - The number of command-line arguments that should be consumed.
    // const - A constant value required by some action and nargs selections.
    // default - The value produced if the argument is absent from the command line and if it is absent from the namespace object.
    // type - The type to which the command-line argument should be converted.
    // choices - A sequence of the allowable values for the argument.
    // required - Whether or not the command-line option may be omitted (optionals only).
    // help - A brief description of what the argument does.
    // metavar - A name for the argument in usage messages.
    // dest - The name of the attribute to be added to the object returned by parse_args().
    // deprecated - Whether or not use of the argument is deprecated.

    name: []const u8,
    short_flags: ?[]const u21 = null,
    long_flags: ?[]const []const u8 = null,
    nargs: u32 = 0,
    action: ArgumentAction = .store,
    description: ?[]const u8 = null,
};

const ArgumentParser = struct {
    arena_ptr: *std.heap.ArenaAllocator,
    args: std.ArrayList(Argument),
    subcommands: SubParserHashMap,

    fn add_argument(self: *ArgumentParser, arg: Argument) !void {
        try self.args.append(arg);
    }
};
