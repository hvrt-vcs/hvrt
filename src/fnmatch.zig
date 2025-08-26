const std = @import("std");
const fspath = std.fs.path;

const c = @import("c.zig");

// This is not a regex, but we can use similar concepts here. To start, we'll make a state machine:
// * https://swtch.com/~rsc/regexp/regexp1.html
// * https://swtch.com/~rsc/regexp/regexp2.html
// * https://swtch.com/~rsc/regexp/regexp3.html

/// Copied and modified from stdlib
pub const Utf8Iterator = struct {
    bytes: []const u8,
    i: usize,

    pub fn init(s: std.unicode.Utf8View) Utf8Iterator {
        return Utf8Iterator{
            .bytes = s.bytes,
            .i = 0,
        };
    }
    pub fn nextCodepointSlice(it: *Utf8Iterator) ?[]const u8 {
        if (it.i >= it.bytes.len) {
            return null;
        }

        const cp_len = std.unicode.utf8ByteSequenceLength(it.bytes[it.i]) catch unreachable;
        it.i += cp_len;
        return it.bytes[it.i - cp_len .. it.i];
    }

    pub fn nextCodepoint(it: *Utf8Iterator) ?u21 {
        const slice = it.nextCodepointSlice() orelse return null;
        return std.unicode.utf8Decode(slice) catch unreachable;
    }

    /// Look ahead at the next n codepoints without advancing the iterator.
    /// If fewer than n codepoints are available, then return the remainder of the string.
    pub fn peek(it: *Utf8Iterator, n: usize) []const u8 {
        const original_i = it.i;
        defer it.i = original_i;

        var end_ix = original_i;
        var found: usize = 0;
        while (found < n) : (found += 1) {
            const next_codepoint = it.nextCodepointSlice() orelse return it.bytes[original_i..];
            end_ix += next_codepoint.len;
        }

        return it.bytes[original_i..end_ix];
    }

    /// Look ahead at one codepoint without advancing the iterator.
    pub fn peekCodepoint(it: *Utf8Iterator) ?u21 {
        const original_i = it.i;
        defer it.i = original_i;

        return it.nextCodepoint();
    }
};

pub const Flags = packed struct {
    file_name: bool = false,
    period: bool = false,
    no_escape: bool = false,
    leading_dir: bool = false,
};

const special_runes: []const u21 = &.{
    '\\',
    '*',
    '?',
    '[',
};

// Just do this the old fashioned way: with a couple of iterators. No need to
// get fancy with state machines or anything like that.
//
// Take inspiration from the following implementations:
// * https://github.com/gcc-mirror/gcc/blob/2dfd2779e373dffaae9532d45267497a6246f661/libiberty/fnmatch.c
// * https://opensource.apple.com/source/Libc/Libc-167/gen.subproj/fnmatch.c.auto.html
pub fn fnmatch(pattern: []const u8, string: []const u8, flags: Flags) !bool {
    const temp_buffer: [std.fs.max_path_bytes * 3]u8 = undefined;
    _ = temp_buffer; // autofix
    _ = flags;

    const string_view = try std.unicode.Utf8View.init(string);
    var string_iter = Utf8Iterator.init(string_view);

    const pattern_view = try std.unicode.Utf8View.init(pattern);
    var pattern_iter = Utf8Iterator.init(pattern_view);

    while (pattern_iter.nextCodepoint()) |pattern_rune| {
        switch (pattern_rune) {
            '\\' => {
                // if no next rune exists to escape, then return false
                const escaped_rune = pattern_iter.nextCodepoint() orelse return false;
                // if end of string before end of pattern, return false
                const string_rune = string_iter.nextCodepoint() orelse return false;

                if (string_rune != escaped_rune) return false;
            },
            '?' => {
                // discard a rune.
                // if end of string before end of pattern, return false
                _ = string_iter.nextCodepoint() orelse return false;
            },
            '*' => {
                // collapse multiple stars
                while (pattern_iter.peekCodepoint()) |maybe_star| {
                    if (maybe_star == '*') {
                        _ = pattern_iter.nextCodepoint();
                    } else {
                        break;
                    }
                }

                // If star is the last character, and everything has matched up
                // to this point, then star will simply match the remainder of
                // the string.
                const peeked_pattern_rune = pattern_iter.peekCodepoint() orelse return true;

                if (std.mem.containsAtLeastScalar(u21, special_runes, 1, peeked_pattern_rune)) {
                    // Pattern rune is special character class.
                    unreachable;

                    // ...
                    // When it doubt, use recursion.
                    // return fnmatch(
                    //     pattern_iter.bytes[pattern_iter.i..],
                    //     string_iter.bytes[string_iter.i..],
                    //     flags,
                    // );
                } else {
                    // Not a special character class. Just a plain old rune.
                    // Iterate until we find it.

                    // There are more pattern char(s) after star. If the string
                    // ends now, there is no way it can match the pattern.
                    var peeked_string_rune = string_iter.peekCodepoint() orelse return false;
                    while (peeked_string_rune != peeked_pattern_rune) {
                        // Can't fail. We already peeked for this codepoint.
                        _ = string_iter.nextCodepoint() orelse unreachable;

                        // The pattern requires more runes to match.
                        peeked_string_rune = string_iter.peekCodepoint() orelse return false;
                    }
                }
            },
            '[' => {
                if (string_iter.nextCodepoint()) |string_rune| {
                    while (pattern_iter.nextCodepoint()) |prune| {
                        // If we hit the end bracket and haven't matched yet,
                        // then the string doesn't match.
                        if (prune == ']') return false;

                        if (string_rune == prune) {
                            // Found a match! Now iterate past the char set.
                            while (pattern_iter.nextCodepoint()) |prune2| {
                                if (prune2 == ']') break;
                            } else {
                                // We iterated and never found an end bracket.
                                return error.BadPattern;
                            }
                            break;
                        }
                    } else {
                        // We iterated the whole pattern and never found a
                        // match or an end bracket.
                        return error.BadPattern;
                    }
                } else {
                    // Length of input string does not match pattern string
                    return false;
                }
            },
            else => {
                if (string_iter.nextCodepoint()) |string_rune| {
                    if (string_rune != pattern_rune) return false;
                } else {
                    // Length of input string does not match pattern string
                    return false;
                }
            },
        }
    }

    // string should be exhausted when pattern is exhausted.
    return string_iter.peekCodepoint() == null;
}

pub fn translate(gpa: std.mem.Allocator) !void {
    _ = gpa; // autofix
}

test fnmatch {
    const alloc = std.testing.allocator;
    _ = alloc; // autofix

    // Leading star
    const match1 = try fnmatch("*bar.baz", "foobar.baz", .{});
    try std.testing.expect(match1);

    // Trailing star
    const match2 = try fnmatch("foobar.*", "foobar.baz", .{});
    try std.testing.expect(match2);

    // Middle star
    const match3 = try fnmatch("foo*.baz", "foobar.baz", .{});
    try std.testing.expect(match3);

    // qmarks
    const match4 = try fnmatch("foo?ar.?az", "foobar.baz", .{});
    try std.testing.expect(match4);

    // Escape
    const match5 = try fnmatch("foobar\\?.baz", "foobar?.baz", .{});
    try std.testing.expect(match5);

    // Char class
    const match6 = try fnmatch("fooba[rzt].baz", "foobar.baz", .{});
    try std.testing.expect(match6);
}

test translate {}

test "refAllDeclsRecursive" {
    std.testing.refAllDeclsRecursive(@This());
}
