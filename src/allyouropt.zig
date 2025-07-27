// This module is influenced by the Python argparse and getopt modules.
// See: https://docs.python.org/3/library/argparse.html
// See: https://docs.python.org/3/library/getopt.html
const std = @import("std");
const c = @import("c.zig");

const log = std.log.scoped(.allyouropt);

pub const ParsedOpt = struct {
    flag: []const u8,
    arg_index: usize,
    value: ?[]const u8 = null,
};

pub const OptIterator = struct {
    args: []const []const u8,
    short_flags: []const u8,
    long_flags: []const []const u8,
    arg_index: usize = 0,

    pub fn next(self: *OptIterator) ?ParsedOpt {
        // while args and args[0].startswith('-') and args[0] != '-':
        //     if args[0] == '--':
        //         args = args[1:]
        //         break
        //     if args[0].startswith('--'):
        //         opts, args = do_longs(opts, args[0][2:], longopts, args[1:])
        //     else:
        //         opts, args = do_shorts(opts, args[0][1:], shortopts, args[1:])

        if (self.arg_index >= self.args.len) return null;

        const arg = self.args[self.arg_index];

        if (std.mem.startsWith(u8, arg, "-") and !std.mem.eql(u8, arg, "-")) {
            if (std.mem.eql(u8, arg, "--")) {
                // a double dash alone means that opt parsing is done, and
                // everything else is args, even if those args start with
                // dashes.
                return null;
            } else if (std.mem.startsWith(u8, arg, "--")) {
                // long opt
                return self.do_long_flag(arg);
            } else {
                // short opts
                return self.do_short_flag(arg);
            }
        }

        return null;
    }

    fn do_long_flag(self: *OptIterator, arg: []const u8) ?ParsedOpt {
        // long opts

        const trimmed = std.mem.trimLeft(u8, arg, "-");
        const eql_index_opt = std.mem.indexOfScalar(u8, trimmed, '=');

        const before_eql = if (eql_index_opt) |i| trimmed[0..i] else trimmed;

        for (self.long_flags) |flag| {
            if (std.mem.startsWith(u8, flag, before_eql)) {
                if (std.mem.endsWith(u8, flag, "=")) {
                    if (before_eql.len < trimmed.len) {
                        // Value is part of the same argument after the '=' symbol.
                        defer self.arg_index += 1;
                        return .{
                            .flag = flag,
                            .arg_index = self.arg_index,
                            .value = trimmed[(eql_index_opt.?)..],
                        };
                    } else {
                        // Value is the next argument.
                        if (self.arg_index + 1 >= self.args.len) {
                            // too few arguments
                            return null;
                        } else {
                            // Add two to skip required arg
                            defer self.arg_index += 2;
                            return .{
                                .flag = flag,
                                .arg_index = self.arg_index,
                                .value = self.args[self.arg_index + 1],
                            };
                        }
                    }
                } else {
                    // No value required for flag
                    defer self.arg_index += 1;
                    return .{
                        .flag = flag,
                        .arg_index = self.arg_index,
                        .value = null,
                    };
                }
            }
        }
        return null;
    }

    fn do_short_flag(self: *OptIterator, arg: []const u8) ?ParsedOpt {
        const trimmed = std.mem.trimLeft(u8, arg, "-");
        const eql_index_opt = std.mem.indexOfScalar(u8, trimmed, '=');

        const before_eql = if (eql_index_opt) |i| trimmed[0..i] else trimmed;

        if (before_eql.len > 1 or before_eql.len == 0) {
            // Currently only support one flag per dash
            return null;
        }

        const flag_index_opt = std.mem.indexOfScalar(u8, self.short_flags, before_eql[0]);

        if (flag_index_opt) |flag_index| {
            //
            const flag = self.short_flags[flag_index..(flag_index + 1)];
            if (flag_index + 1 < self.short_flags.len and (self.short_flags[flag_index + 1] == ':')) {
                // Has a required argument
                if (before_eql.len < trimmed.len) {
                    // Value is part of the same argument after the '=' symbol.
                    defer self.arg_index += 1;
                    return .{
                        .flag = flag,
                        .arg_index = self.arg_index,
                        .value = trimmed[(eql_index_opt.?)..],
                    };
                } else {
                    // Value is the next argument.
                    if (self.arg_index + 1 >= self.args.len) {
                        // too few arguments
                        return null;
                    } else {
                        // Add two to skip required arg
                        defer self.arg_index += 2;
                        return .{
                            .flag = flag,
                            .arg_index = self.arg_index,
                            .value = self.args[self.arg_index + 1],
                        };
                    }
                }
            } else {
                // No value required for flag
                defer self.arg_index += 1;
                return .{
                    .flag = self.short_flags[flag_index..(flag_index + 1)],
                    .arg_index = self.arg_index,
                    .value = null,
                };
            }
        } else {
            // No such flag
            return null;
        }

        return null;
    }
};

test "invoke with unimplemented subcommand" {
    const basic_args = [_][:0]const u8{ "test_prog_name", "cp" };

    var opt_iter = OptIterator{
        .args = &basic_args,
        .short_flags = &.{},
        .long_flags = &.{},
    };

    while (opt_iter.next()) |o| {
        log.debug("What is the next option? {any}", .{o});
    }
}
