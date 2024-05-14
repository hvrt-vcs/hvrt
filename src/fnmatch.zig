const std = @import("std");
const fspath = std.fs.path;

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
    pub fn peekCodepoint(it: *Utf8Iterator) ?21 {
        const original_i = it.i;
        defer it.i = original_i;

        return it.nextCodepoint();
    }
};

// Just do this the old fashioned way: with a couple of iterators. No need to
// get fancy with state machines or anything like that.
//
// Take inspiration from the following implementations:
// * https://github.com/gcc-mirror/gcc/blob/master/libiberty/fnmatch.c
// * https://opensource.apple.com/source/Libc/Libc-167/gen.subproj/fnmatch.c.auto.html
pub fn fnmatch(pattern: []const u8, string: []const u8, flags: u32) bool {
    _ = flags; // autofix

    const string_view = try std.unicode.Utf8View.init(string);
    var string_iter = Utf8Iterator.init(string_view);

    const pattern_view = try std.unicode.Utf8View.init(pattern);
    var pattern_iter = Utf8Iterator.init(pattern_view);

    while (pattern_iter.nextCodepoint()) |pattern_rune| {
        switch (pattern_rune) {
            '\\' => {
                // if no next rune exists to escape, then return false
                const escaped_rune = pattern_iter.nextCodepoint() or return false;
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

                // star can match against nothing
                if (string_iter.peekCodepoint() == null) return true;

                // // Use recursion to solve this, somehow.
                // return fnmatch(
                //     pattern_iter.bytes[pattern_iter.i..],
                //     string_iter.bytes[string_iter.i..],
                //     flags,
                // );
            },
            '[' => {},
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
