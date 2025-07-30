// This module is influenced by the Python argparse and getopt modules.
// See: https://docs.python.org/3/library/argparse.html
// See: https://docs.python.org/3/library/getopt.html
const std = @import("std");

const log = std.log.scoped(.allyouropt);

pub const Opt = struct {
    name: []const u8,
    short_flags: []const u8 = &.{},
    long_flags: []const []const u8 = &.{},
    takes_arg: bool = false,
};

pub const ParsedOpt = struct {
    opt: Opt,
    arg_index: usize,
    value: ?[]const u8 = null,

    pub fn to_int(self: ParsedOpt, comptime T: type) !T {
        if (self.value) |value| {
            return try std.fmt.parseInt(T, value, 0);
        } else {
            return error.NoValue;
        }
    }

    pub fn to_float(self: ParsedOpt, comptime T: type) !T {
        if (self.value) |value| {
            return try std.fmt.parseFloat(T, value);
        } else {
            return error.NoValue;
        }
    }

    pub fn to_bool(self: ParsedOpt) !bool {
        if (self.value) |value| {
            if (value.len > 5) return error.NotBool;
            var buf: [5]u8 = undefined;
            const lowered = std.ascii.lowerString(&buf, value);

            if (std.mem.eql(u8, lowered, "true")) {
                return true;
            } else if (std.mem.eql(u8, lowered, "false")) {
                return false;
            } else {
                return error.NotBool;
            }
        } else {
            return error.NoValue;
        }
    }
};

pub const OptIterator = struct {
    args: []const []const u8,
    opt_defs: []const Opt = &.{},
    arg_index: usize = 0,

    pub fn next(self: *OptIterator) ?ParsedOpt {
        const arg = if (self.arg_index < self.args.len) self.args[self.arg_index] else return null;

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
                // short opt
                return self.do_short_flag(arg);
            }
        } else {
            // it's an arg, not an opt.
            return null;
        }
    }

    pub fn remaining_args(self: OptIterator) []const []const u8 {
        return self.args[self.arg_index..];
    }

    fn do_long_flag(self: *OptIterator, arg: []const u8) ?ParsedOpt {
        // long opts

        const trimmed = std.mem.trimLeft(u8, arg, "-");
        const eql_index_opt = std.mem.indexOfScalar(u8, trimmed, '=');

        const before_eql = if (eql_index_opt) |i| trimmed[0..i] else trimmed;

        for (self.opt_defs) |opt| {
            for (opt.long_flags) |lflag| {
                if (std.mem.eql(u8, lflag, before_eql)) {
                    if (opt.takes_arg) {
                        if (before_eql.len < trimmed.len) {
                            // Value is part of the same argument after the '=' symbol.
                            defer self.arg_index += 1;
                            return .{
                                .opt = opt,
                                .arg_index = self.arg_index,
                                .value = trimmed[(eql_index_opt.? + 1)..],
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
                                    .opt = opt,
                                    .arg_index = self.arg_index,
                                    .value = self.args[self.arg_index + 1],
                                };
                            }
                        }
                    } else {
                        // Take no argument.
                        defer self.arg_index += 1;
                        return .{
                            .opt = opt,
                            .arg_index = self.arg_index,
                            .value = null,
                        };
                    }
                }
            }
        } else {
            // No such flag
            return null;
        }
    }

    fn do_short_flag(self: *OptIterator, arg: []const u8) ?ParsedOpt {
        const trimmed = std.mem.trimLeft(u8, arg, "-");
        const eql_index_opt = std.mem.indexOfScalar(u8, trimmed, '=');

        const before_eql = if (eql_index_opt) |i| trimmed[0..i] else trimmed;

        if (before_eql.len > 1 or before_eql.len == 0) {
            // Currently only support one flag per dash
            return null;
        }

        const flag_char = before_eql[0];

        for (self.opt_defs) |opt| {
            for (opt.short_flags) |short_flag| {
                if (flag_char == short_flag) {
                    if (opt.takes_arg) {
                        // Has a required argument
                        if (before_eql.len < trimmed.len) {
                            // Value is part of the same argument after the '=' symbol.
                            defer self.arg_index += 1;
                            return .{
                                .opt = opt,
                                .arg_index = self.arg_index,
                                .value = trimmed[(eql_index_opt.? + 1)..],
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
                                    .opt = opt,
                                    .arg_index = self.arg_index,
                                    .value = self.args[self.arg_index + 1],
                                };
                            }
                        }
                    } else {
                        // No value required for flag
                        defer self.arg_index += 1;
                        return .{
                            .opt = opt,
                            .arg_index = self.arg_index,
                            .value = null,
                        };
                    }
                }
            }
        } else {
            // No such flag
            return null;
        }
    }
};

test OptIterator {
    // Happy path for all opts
    const basic_args = [_][:0]const u8{ "test_prog_name", "-a", "-b", "-d=true", "-d", "false", "--gggg", "--ffff=123", "--ffff", "123.4", "--", "cp" };
    const sans_prog = basic_args[1..];

    const opt_defs1: []const Opt = &.{
        .{
            .name = "a",
            .short_flags = "a",
        },
        .{
            .name = "b",
            .short_flags = "b",
        },
        .{
            .name = "d",
            .short_flags = "d",
            .takes_arg = true,
        },
        .{
            .name = "gggg",
            .long_flags = &.{"gggg"},
        },
        .{
            .name = "ffff",
            .long_flags = &.{"ffff"},
            .takes_arg = true,
        },
    };

    var opt_iter1 = OptIterator{
        .args = sans_prog,
        .opt_defs = opt_defs1,
    };

    var d_value_opt: ?bool = null;
    while (opt_iter1.next()) |o| {
        // std.debug.print("What is the next option? {s} {?s} {any}\n", .{ o.opt.name, o.value, o });
        if (std.mem.eql(u8, "d", o.opt.name)) {
            // std.debug.print("Did we hit d? {s} {?s} {any}\n", .{ o.opt.name, o.value, o });
            d_value_opt = try o.to_bool();

            try std.testing.expectError(error.InvalidCharacter, o.to_int(i64));

            try std.testing.expectError(error.InvalidCharacter, o.to_float(f64));
        }
        if (std.mem.eql(u8, "ffff", o.opt.name)) {
            // std.debug.print("What is the next option? {s} {?s} {any}\n", .{ o.opt.name, o.value, o });
            try std.testing.expectError(error.NotBool, o.to_bool());
        }
        if (std.mem.eql(u8, "b", o.opt.name)) {
            // std.debug.print("What is the next option? {s} {?s} {any}\n", .{ o.opt.name, o.value, o });
            try std.testing.expectError(error.NoValue, o.to_bool());
            try std.testing.expectError(error.NoValue, o.to_int(i64));
            try std.testing.expectError(error.NoValue, o.to_float(f64));
        }
    }

    try std.testing.expectEqual(false, d_value_opt.?);
    try std.testing.expectEqual(9, opt_iter1.arg_index);
    try std.testing.expectEqualStrings("--", sans_prog[opt_iter1.arg_index]);

    const opt_defs2: []const Opt = &.{
        .{
            .name = "a",
            .short_flags = "a",
        },
        .{
            .name = "d",
            .short_flags = "d",
            .takes_arg = true,
        },
        .{
            .name = "gggg",
            .long_flags = &.{"gggg"},
        },
        .{
            .name = "ffff",
            .long_flags = &.{"ffff"},
            .takes_arg = true,
        },
    };

    // How does it react when the short flag doesn't exist?
    var opt_iter2 = OptIterator{
        .args = sans_prog,
        .opt_defs = opt_defs2,
    };

    while (opt_iter2.next()) |o| {
        log.debug("What is the next option? {any}", .{o});
        // std.debug.print("What is the next option? {any}", .{o});
    }

    try std.testing.expectEqual(1, opt_iter2.arg_index);
    try std.testing.expectEqualStrings("-b", sans_prog[opt_iter2.arg_index]);

    const opt_defs3: []const Opt = &.{
        .{
            .name = "a",
            .short_flags = "a",
        },
        .{
            .name = "b",
            .short_flags = "b",
        },
        .{
            .name = "d",
            .short_flags = "d",
            .takes_arg = true,
        },
        .{
            .name = "ffff",
            .long_flags = &.{"ffff"},
            .takes_arg = true,
        },
    };

    // How does it react when the long flag doesn't exist?
    var opt_iter3 = OptIterator{
        .args = sans_prog,
        .opt_defs = opt_defs3,
    };

    while (opt_iter3.next()) |o| {
        log.debug("What is the next option? {any}", .{o});
        // std.debug.print("What is the next option? {any}", .{o});
    }

    try std.testing.expectEqual(5, opt_iter3.arg_index);
    try std.testing.expectEqualStrings("--gggg", sans_prog[opt_iter3.arg_index]);
    try std.testing.expectEqual(6, opt_iter3.remaining_args().len);
    try std.testing.expectEqualStrings("--gggg", opt_iter3.remaining_args()[0]);

    const sans_prog2: []const []const u8 = &.{ "-a", "-ab", "arg1", "arg2" };

    // How does it react to multiple short flags?
    var opt_iter4 = OptIterator{
        .args = sans_prog2,
        .opt_defs = opt_defs3,
    };

    while (opt_iter4.next()) |o| {
        log.debug("What is the next option? {any}", .{o});
        // std.debug.print("What is the next option? {any}", .{o});
    }

    try std.testing.expectEqual(1, opt_iter4.arg_index);
    try std.testing.expectEqualStrings("-ab", sans_prog2[opt_iter4.arg_index]);
    try std.testing.expectEqual(3, opt_iter4.remaining_args().len);
    try std.testing.expectEqualStrings("-ab", opt_iter4.remaining_args()[0]);
}
