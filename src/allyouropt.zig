// This module is influenced by the Python argparse and getopt modules.
// See: https://docs.python.org/3/library/argparse.html
// See: https://docs.python.org/3/library/getopt.html
const std = @import("std");
const c = @import("c.zig");

const log = std.log.scoped(.allyouropt);

// pub const Opt = struct {
//     name: []const u8,
//     short_flags: []const u8,
//     long_flags: []const []const u8,
//     takes_arg: bool = false,
// };

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

    pub fn remaining_args(self: OptIterator) []const []const u8 {
        return self.args[self.arg_index..];
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

test OptIterator {
    // Happy path for all opts
    const basic_args = [_][:0]const u8{ "test_prog_name", "-a", "-b", "-d=foo", "-d", "bar", "--gggg", "--ffff=foo", "--ffff", "bar", "cp" };
    const sans_prog = basic_args[1..];

    var opt_iter1 = OptIterator{
        .args = sans_prog,
        .short_flags = "abcd:",
        .long_flags = &.{ "eeee", "ffff=", "gggg" },
    };

    while (opt_iter1.next()) |o| {
        log.debug("What is the next option? {any}", .{o});
    }

    try std.testing.expectEqual(9, opt_iter1.arg_index);
    try std.testing.expectEqualStrings("cp", sans_prog[opt_iter1.arg_index]);

    // How does it react when the short flag doesn't exist?
    var opt_iter2 = OptIterator{
        .args = sans_prog,
        .short_flags = "acd:",
        .long_flags = &.{ "eeee", "ffff=", "gggg" },
    };

    while (opt_iter2.next()) |o| {
        log.debug("What is the next option? {any}", .{o});
        // std.debug.print("What is the next option? {any}", .{o});
    }

    try std.testing.expectEqual(1, opt_iter2.arg_index);
    try std.testing.expectEqualStrings("-b", sans_prog[opt_iter2.arg_index]);

    // How does it react when the long flag doesn't exist?
    var opt_iter3 = OptIterator{
        .args = sans_prog,
        .short_flags = "abcd:",
        .long_flags = &.{ "eeee", "ffff=" },
    };

    while (opt_iter3.next()) |o| {
        log.debug("What is the next option? {any}", .{o});
        // std.debug.print("What is the next option? {any}", .{o});
    }

    try std.testing.expectEqual(5, opt_iter3.arg_index);
    try std.testing.expectEqualStrings("--gggg", sans_prog[opt_iter3.arg_index]);
    try std.testing.expectEqual(5, opt_iter3.remaining_args().len);
    try std.testing.expectEqualStrings("--gggg", opt_iter3.remaining_args()[0]);
}
