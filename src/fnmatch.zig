const std = @import("std");

// This is not a regex, but we can use similar concepts here. To start, we'll make a state machine:
// * https://swtch.com/~rsc/regexp/regexp1.html
// * https://swtch.com/~rsc/regexp/regexp2.html
// * https://swtch.com/~rsc/regexp/regexp3.html

/// Wraps a stdlib Utf8Iterator and adds some peek functions to it.
pub const Utf8Iterator = struct {
    iter: std.unicode.Utf8Iterator,

    pub fn init(s: std.unicode.Utf8View) Utf8Iterator {
        return Utf8Iterator{
            .iter = s.iterator(),
        };
    }

    pub fn nextCodepoint(it: *Utf8Iterator) ?u21 {
        return it.iter.nextCodepoint();
    }

    /// Look ahead at one codepoint without advancing the iterator.
    pub fn peekCodepoint(it: *Utf8Iterator) ?u21 {
        const original_i = it.iter.i;
        defer it.iter.i = original_i;

        return it.iter.nextCodepoint();
    }

    /// Progress to the next index.
    ///
    /// Return `null` if the iterator cannot iterate anymore.
    pub fn nextIndex(it: *Utf8Iterator) ?usize {
        if (it.iter.nextCodepoint()) |_| {
            return it.iter.i;
        } else {
            return null;
        }
    }

    /// Look ahead at the next index without advancing the iterator.
    ///
    /// Return `null` if the iterator cannot iterate anymore.
    pub fn peekIndex(it: *Utf8Iterator) ?usize {
        const original_i = it.iter.i;
        defer it.iter.i = original_i;

        return it.nextIndex();
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

                    // The current index indicates the next rune.
                    const next_pattern_index = pattern_iter.iter.i;
                    const next_pattern = pattern_iter.iter.bytes[next_pattern_index..];

                    var cur_index_opt: ?usize = string_iter.iter.i;
                    while (cur_index_opt) |next_index| : (cur_index_opt = string_iter.nextIndex()) {
                        // This isn't an optimized solution,
                        // since it causes backtracking.
                        // However it generates the correct result.
                        //
                        // When in doubt, use brute force.
                        const next_str = string_iter.iter.bytes[(next_index)..];
                        const is_match = try fnmatch(
                            next_pattern,
                            next_str,
                            flags,
                        );

                        if (is_match) {
                            return true;
                        } else {
                            continue;
                        }
                    } else {
                        // We iterated through the whole rest of the string to
                        // try to find a match for the next special char and
                        // didn't find a match.
                        return false;
                    }
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
                    while (pattern_iter.nextCodepoint()) |pattern_rune2| {
                        // If we hit the end bracket and haven't matched yet,
                        // then the string doesn't match.
                        if (pattern_rune2 == ']') return false;

                        if (string_rune == pattern_rune2) {
                            // Found a match! Now iterate past the char set.
                            while (pattern_iter.nextCodepoint()) |pattern_rune3| {
                                if (pattern_rune3 == ']') break;
                            } else {
                                // We iterated and never found an end bracket.
                                std.log.warn("bad pattern with match {s}\n", .{pattern});
                                return error.BadPattern;
                            }
                            break;
                        }
                    } else {
                        // We iterated the whole pattern and never found a
                        // match or an end bracket.
                        std.log.warn("bad pattern without match {s}\n", .{pattern});
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

test fnmatch {
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

    // special char after star #1
    const match7 = try fnmatch("fooba*[rzt].baz", "foobar.baz", .{});
    try std.testing.expect(match7);

    // special char after star #2
    const match8 = try fnmatch("foob*[rzt].baz", "foobar.baz", .{});
    try std.testing.expect(match8);
}

test "refAllDeclsRecursive" {
    std.testing.refAllDeclsRecursive(@This());
}
