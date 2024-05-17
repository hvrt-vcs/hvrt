const std = @import("std");
const c = @import("c.zig");
const utf = std.unicode;

const Pcre2Code = union(enum) {
    utf8: *c.pcre2_code_8,
    utf16: *c.pcre2_code_16,
    utf32: *c.pcre2_code_32,
};

/// A basic wrapper around raw pcre2 API. See docs here:
/// https://www.pcre.org/current/doc/html/pcre2api.html
pub const Matcher = struct {
    // Eventually wrap allocator in a pcre2 context.
    alloc: std.mem.Allocator,
    matcher: Pcre2Code,

    /// Must call `free` on returned object, or memory will be leaked.
    pub fn compile(alloc: std.mem.Allocator, regex: []const u8) !Matcher {
        const options: u32 = 0;
        var errorcode: c_int = 0;
        var erroroffset: usize = 0;
        const context: ?*c.pcre2_compile_context_8 = null;
        var error_msg_buf: [1024 * 4]u8 = undefined;

        const utf8view = try utf.Utf8View.init(regex);
        var utf8_iter = utf8view.iterator();

        var max_bytes: u3 = 0;
        while (utf8_iter.nextCodepointSlice()) |slc| {
            const nbytes = utf.utf8ByteSequenceLength(slc[0]) catch unreachable;
            max_bytes = @max(max_bytes, nbytes);
        }

        return switch (max_bytes) {
            0 => {
                return error.EmptyRegex;
            },
            1 => {
                // use pcre2_compile_8
                const matcher_opt = c.pcre2_compile_8(regex.ptr, regex.len, options, &errorcode, &erroroffset, context);

                if (matcher_opt) |matcher| {
                    return .{ .matcher = .{ .utf8 = matcher }, .alloc = alloc };
                } else {
                    const error_msg_size = c.pcre2_get_error_message_8(errorcode.*, &error_msg_buf, error_msg_buf.len);
                    const error_msg_final = error_msg_buf[0..error_msg_size];
                    std.debug.print(
                        "Regex '{s}' failed to compile with errorcode {} at offset {} with message '{s}'",
                        .{ regex, errorcode.*, erroroffset.*, error_msg_final },
                    );
                    return error.Pcre2Error;
                }
            },
            2 => {
                // use pcre2_compile_16
                unreachable;
            },
            3, 4 => {
                // use pcre2_compile_32
                var array32 = std.ArrayList(u32).init(alloc);
                defer array32.deinit();

                var utf8_iter2 = utf8view.iterator();

                const cp_count = utf.utf8CountCodepoints(regex) catch unreachable;

                try array32.ensureTotalCapacityPrecise(cp_count);

                while (utf8_iter2.nextCodepoint()) |codepoint| {
                    array32.appendAssumeCapacity(codepoint);
                }

                unreachable;
            },
        };
    }

    pub fn free(self: Matcher) void {
        c.pcre2_code_free_8(self.matcher);
    }

    /// Docs: https://www.pcre.org/current/doc/html/pcre2api.html#SEC39
    pub fn dfa_match(self: Matcher, string: []const u8, start_offset: ?usize) bool {
        const options: u32 = 0;
        const context: ?*c.pcre2_compile_context_8 = null;
        const md: ?*c.pcre2_match_data_8 = null;
        var workspace: [20]c_int = undefined;
        c.pcre2_dfa_match_8(self.matcher, string.ptr, string.len, start_offset orelse 0, options, md, context, &workspace, workspace.len);
    }
};

test "Matcher" {
    _ = Matcher;

    const matcher = try Matcher.compile(".*some literals\\w");

    const matches = matcher.dfa_match("blah blah", null);

    try std.testing.expect(matches);
}
