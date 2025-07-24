// This module is somewhat modelled on the Python argparse module.
// See: https://docs.python.org/3/library/argparse.html
const std = @import("std");
const c = @import("c.zig");

const SubParserHashMap = std.array_hash_map.StringArrayHashMap(*ArgumentParser);
const ArgList = std.ArrayList(Argument);

const log = std.log.scoped(.argparse);

pub const ArgAction = enum {
    store,
    store_const,
    store_true,
    store_false,
    append,
    append_const,
    extend,
    count,
    help,
    version,
};

pub const ArgType = enum {
    boolean,
    int,
    float,
    str,
    str_array,
};

pub const StringArrayList = std.ArrayList([]const u8);

pub const ArgValue = union(ArgType) {
    boolean: bool,
    int: i64,
    float: f64,
    str: []const u8,
    str_array: *StringArrayList,
};

/// Convert to the preferred type. Raise an error if the value is not valid.
/// argparse will handle an error gracefully and print out a friendly message
/// with the error value.
pub const ArgCaster = *const fn (arg: []const u8) anyerror!ArgValue;

pub fn noopArgCaster(arg: []const u8) anyerror!ArgValue {
    return .{ .str = arg };
}

pub fn boolArgCaster(arg: []const u8) anyerror!ArgValue {
    const trimmed = std.mem.trim(u8, arg, " \n");

    if (trimmed.len > 5) return error.NotBoolean;
    var output: [5]u8 = undefined;
    const lowered = std.ascii.lowerString(&output, trimmed);

    if (std.mem.eql(u8, "true", lowered)) {
        return .{ .boolean = true };
    } else if (std.mem.eql(u8, "false", lowered)) {
        return .{ .boolean = false };
    } else {
        return error.NotBoolean;
    }
}

pub fn intArgCaster(arg: []const u8) anyerror!ArgValue {
    const int_val = try std.fmt.parseInt(i64, arg, 0);
    return .{ .int = int_val };
}

pub fn floatArgCaster(arg: []const u8) anyerror!ArgValue {
    const float_val = try std.fmt.parseFloat(f64, arg);
    return .{ .float = float_val };
}

pub const NargType = enum {
    zero_or_one,
    zero_or_more,
    one_or_more,
};

pub const Argument = struct {
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
    action: ArgAction = .store,
    nargs: union { arg_num: u16, arg_type: NargType } = .{ .arg_num = 1 },
    constant: ?ArgValue = null,
    default: ?ArgValue = null,
    arg_type: ArgCaster = noopArgCaster,
    choices: []const []const u8 = &.{},
    required: bool = false,
    help: ?[]const u8 = null,
    metavar: ?[]const u8 = null,
    dest: ?[]const u8 = null,
    deprecated: bool = false,
};

pub const ArgumentParser = struct {
    arena_ptr: *std.heap.ArenaAllocator,
    args_ptr: *ArgList,
    subcommands_ptr: *SubParserHashMap,

    pub fn init(gpa: std.mem.Allocator) !ArgumentParser {
        const arena_ptr = try gpa.create(std.heap.ArenaAllocator);
        errdefer gpa.destroy(arena_ptr);
        arena_ptr.* = std.heap.ArenaAllocator.init(gpa);

        const args_ptr = try arena_ptr.allocator().create(ArgList);
        args_ptr.* = ArgList.init(arena_ptr.allocator());

        const subcommands_ptr = try arena_ptr.allocator().create(SubParserHashMap);
        subcommands_ptr.* = SubParserHashMap.init(arena_ptr.allocator());

        return .{
            .arena_ptr = arena_ptr,
            .args_ptr = args_ptr,
            .subcommands_ptr = subcommands_ptr,
        };
    }

    pub fn deinit(self: *const ArgumentParser) void {
        const child_allocator = self.arena_ptr.child_allocator;
        self.arena_ptr.deinit();
        child_allocator.destroy(self.arena_ptr);
    }

    pub fn add_argument(self: *const ArgumentParser, arg: Argument) !void {
        try self.args_ptr.append(arg);
    }

    pub fn parse_args(self: *const ArgumentParser, raw_args: []const [:0]const u8) !void {
        _ = self;
        _ = raw_args;
    }
};
