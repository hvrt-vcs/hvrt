// This module is influenced by the Python argparse and getopt modules.
// See: https://docs.python.org/3/library/argparse.html
// See: https://docs.python.org/3/library/getopt.html
const std = @import("std");
const c = @import("c.zig");

const log = std.log.scoped(.allyouropt);

/// A struct defining an option.
///
/// At least one of `short_flags` or `long_flags` is required. A single option
/// can have multiple long and short flags.
pub const Option = struct {
    name: []const u8,
    short_flags: ?[]const u21 = null,
    long_flags: ?[]const []const u8 = null,

    /// All options are considered boolean flags by default (i.e. they do not
    /// take an argument). However, if a value is given for `arg_validator`
    /// then the option is considered to have an argument associated with it.
    ///
    /// As the name implies, an `ArgValidator` validates that the string
    /// argument is in an expected format. If the argument does not conform
    /// to the expected format, then an error should be returned.
    ///
    /// An `Option` is defined to either have an argument or not: `Option`
    /// arguments cannot be optional.
    arg_validator: ?ArgValidator = null,

    /// An array of allowable string choices. An argument must conform to one
    /// of these, otherwise an error is returned.
    ///
    /// It is illegal to define both `arg_validator` and `choices` for the same
    /// Option.
    ///
    /// Providing `choices` means that the `Option` will have a required
    /// argument, which *must* be one of the given choices.
    choices: ?[]const []const u8 = null,

    /// An optional help message to print for the `fmt_help` and `print_help`
    /// member functions.
    help: ?[]const u8,

    pub fn requiresArgument(self: Option) bool {
        return self.arg_validator != null or self.choices != null;
    }

    pub fn matchesFlag(self: Option, arg: []const u8) bool {
        const is_long = std.mem.startsWith(u8, arg, "--");
        const trimmed = std.mem.trimLeft(u8, arg, "-");

        if (is_long) {
            if (self.long_flags) |long_flags| {
                for (long_flags) |flag| {
                    if (std.mem.eql(u8, flag, trimmed)) {
                        return true;
                    }
                }
            }
        } else {
            if (self.short_flags) |short_flags| {
                if (trimmed.len > 0) {
                    // Convert to codepoint first, since this may be a
                    // multibyte character.
                    //
                    // TODO: deal with multiple short flags, like `-vrf`.
                    var utf8 = (try std.unicode.Utf8View.init(trimmed)).iterator();
                    if (utf8.nextCodepoint()) |codepoint| {
                        return std.mem.indexOfScalar(u21, short_flags, codepoint) != null;
                    }
                }
            }
        }
        return false;
    }

    pub fn validateArg(self: Option, arg: []const u8) !void {
        if (self.arg_validator) |arg_validator| {
            try arg_validator(arg);
            return;
        } else if (self.choices) |choices| {
            for (choices) |choice| {
                if (std.mem.eql(u8, arg, choice)) {
                    return;
                }
            } else {
                return error.NoMatchingChoice;
            }
        } else {
            // When there are no validators, all args are valid.
            return;
        }
    }

    pub fn checkHasFLags(self: Option) !void {
        const no_shorts = if (self.short_flags) |sf| sf.len == 0 else true;
        const no_longs = if (self.long_flags) |lf| lf.len == 0 else true;
        if (no_shorts and no_longs) {
            return error.NoFlagsGiven;
        }
    }

    pub fn checkValidators(self: Option) !void {
        if (self.arg_validator) {
            if (self.choices) {
                return error.MultipleValidationMethods;
            }
        }
    }

    pub fn checkAll(self: Option) !void {
        self.checkHasFLags();
        self.checkValidators();
    }
};

/// The value returned when iterator over an ArgsIterator.
pub const ParsedOption = struct {
    name: []const u8,
    flag: []const u8,
    opt_arg: []const u8,
    raw_arg: ?[]const u8 = null,
    arg: ?[]const u8 = null,
};

/// Raise an error if the value is not valid.
pub const ArgValidator = *const fn (arg: []const u8) anyerror!void;

/// A simple noop validator that never returns an error.
pub fn noopValidator(arg: []const u8) anyerror!void {
    _ = arg;
    return;
}

pub fn boolValidator(arg: []const u8) anyerror!void {
    const trimmed = std.mem.trim(u8, arg, " \n");

    if (trimmed.len > 5) return error.NotBoolean;
    var output: [5]u8 = undefined;
    const lowered = std.ascii.lowerString(&output, trimmed);

    if (std.mem.eql(u8, "true", lowered) or std.mem.eql(u8, "false", lowered)) {
        return;
    } else {
        return error.NotBoolean;
    }
}

pub fn intValidator(arg: []const u8) anyerror!void {
    _ = try std.fmt.parseInt(i64, arg, 0);
}

pub fn floatValidator(arg: []const u8) anyerror!void {
    _ = try std.fmt.parseFloat(f64, arg);
}

// pub const Argument = struct {
//     // For reference from Python argparse docs:
//     //
//     // name or flags - Either a name or a list of option strings, e.g. 'foo' or '-f', '--foo'.
//     // action - The basic type of action to be taken when this argument is encountered at the command line.
//     // nargs - The number of command-line arguments that should be consumed.
//     // const - A constant value required by some action and nargs selections.
//     // default - The value produced if the argument is absent from the command line and if it is absent from the namespace object.
//     // type - The type to which the command-line argument should be converted.
//     // choices - A sequence of the allowable values for the argument.
//     // required - Whether or not the command-line option may be omitted (optionals only).
//     // help - A brief description of what the argument does.
//     // metavar - A name for the argument in usage messages.
//     // dest - The name of the attribute to be added to the object returned by parse_args().
//     // deprecated - Whether or not use of the argument is deprecated.

//     name: []const u8,
//     short_flags: ?[]const u21 = null,
//     long_flags: ?[]const []const u8 = null,
//     action: ArgAction = .store,
//     nargs: union { arg_num: u16, arg_type: NargType } = .{ .arg_num = 1 },
//     constant: ?ArgValue = null,
//     default: ?ArgValue = null,
//     arg_type: ArgCaster = noopArgCaster,
//     choices: []const []const u8 = &.{},
//     required: bool = false,
//     help: ?[]const u8 = null,
//     metavar: ?[]const u8 = null,
//     dest: ?[]const u8 = null,
//     deprecated: bool = false,
// };

pub const OptOrArg = union {
    option: ParsedOption,
    arg: []const u8,
};

/// Iterates over a sequence of raw arguments and returns `Option` structs.
///
/// When an argument is not recognized as an option, it is returned as a plain
/// positional argument.
pub const ArgIterator = struct {
    args_index: usize = 0,
    opts: []Option,
    raw_args: []const []const u8,

    pub fn next(self: *ArgIterator) !?OptOrArg {
        if (self.args_index > self.raw_args.len) return null;

        // Used when an option and its argument are separated by a space.
        var opt_maybe: ?Option = null;
        var opt_lit_maybe: ?[]const u8 = null;

        for (self.raw_args[self.args_index..]) |arg| {
            defer self.args_index += 1;

            if (opt_maybe) |opt| {
                try opt.validateArg(arg);
                if (opt_lit_maybe) |opt_lit| {
                    return .{
                        .option = .{
                            .name = opt.name,
                            .flag = opt_lit,
                            .opt_arg = opt_lit,
                            .arg = arg,
                            .raw_arg = arg,
                        },
                    };
                } else {
                    unreachable;
                }
            } else {
                if (std.mem.startsWith(u8, arg, "-")) {
                    for (self.opts) |opt| {
                        if (opt.matchesFlag(arg)) {
                            if (opt.requiresArgument()) {
                                opt_maybe = opt;
                                opt_lit_maybe = arg;
                            }
                        }
                    }
                    return OptOrArg{ .arg = arg };
                } else {}
            }
        }
        return null;
    }
};

pub const OptParser = struct {
    opts: []Option,

    pub fn init(opt_slice: []Option) !OptParser {
        for (opt_slice, 0..) |opt, i| {
            opt.checkAll() catch |err| {
                log.warn("Argument {any} (index {any}) is invalid due to reason: {any}", .{ opt, i, err });
                return err;
            };
        }

        return .{
            .opts = opt_slice,
        };
    }

    pub fn iterator(self: OptParser, raw_args: []const []const u8, strip_prog: bool) ArgIterator {
        const args = if (strip_prog and raw_args.len > 0) raw_args[1..] else raw_args;
        return .{
            .opts = self.opts,
            .raw_args = args,
        };
    }

    pub fn fmt_help(self: OptParser, gpa: std.mem.Allocator) ![]const u8 {
        _ = self;
        _ = gpa;
        return &.{};
    }

    pub fn print_help(self: OptParser) !void {
        _ = self;
    }
};
