const std = @import("std");
const c = @import("c.zig");
const unicode = std.unicode;

/// A basic wrapper around raw pcre2 API. See docs here:
/// https://www.pcre.org/current/doc/html/pcre2api.html
pub const Matcher = struct {
    // Eventually wrap allocator in a pcre2 context.
    // alloc: std.mem.Allocator,
    matcher: *c.pcre2_code_8,

    /// Must call `free` on returned object, or memory will be leaked.
    pub fn compile(regex: []const u8) !Matcher {
        if (!unicode.utf8ValidateSlice(regex)) return error.InvalidUtf8;

        const options: u32 = 0;
        var errorcode: c_int = 0;
        var erroroffset: usize = 0;
        const context: ?*c.pcre2_compile_context_8 = null;

        const matcher_opt: ?*c.pcre2_code_8 = c.pcre2_compile_8(
            regex.ptr,
            regex.len,
            options,
            &errorcode,
            &erroroffset,
            context,
        );

        if (matcher_opt) |matcher| {
            return .{ .matcher = matcher };
        } else {
            var error_msg_buf: [1024 * 4]u8 = undefined;
            const error_msg_final = getErrorMessage(errorcode, &error_msg_buf);
            std.debug.print(
                "Regex '{s}' failed to compile with errorcode {} at offset {} with message '{s}'\n",
                .{ regex, errorcode, erroroffset, error_msg_final },
            );
            return error.Pcre2Error;
        }
    }

    pub fn free(self: Matcher) void {
        c.pcre2_code_free_8(self.matcher);
    }

    fn getErrorMessage(error_code: c_int, buffer: []u8) []u8 {
        const error_msg_size = c.pcre2_get_error_message_8(error_code, buffer.ptr, buffer.len);
        const msg_size_cast = @as(usize, @intCast(error_msg_size));
        const error_msg_final = buffer[0..msg_size_cast];
        return error_msg_final;
    }

    pub fn convertGlob(alloc: std.mem.Allocator, glob: []const u8) ![:0]u8 {
        const options: u32 = c.PCRE2_CONVERT_GLOB;
        const context: ?*c.pcre2_convert_context_8 = null;
        var output_opt: ?[*:0]u8 = undefined;
        var output_size_in_code_points: usize = 0;

        const result = c.pcre2_pattern_convert_8(glob.ptr, glob.len, options, &output_opt, &output_size_in_code_points, context);
        defer c.pcre2_converted_pattern_free_8(output_opt);

        if (result != 0) {
            std.debug.print("Something went wrong with glob conversion", .{});
        }

        if (output_opt) |output| {
            // Because the output size is in codepoints, and we're using utf8,
            // it is simpler to just looking for the terminating `0` sentinel
            // and copy from there.
            const size = std.mem.len(output);

            // Once we create a context with the passed in allocator, we can
            // just directly return a slice of this returned cstring.
            const output_slice = output[0..size];
            return try alloc.dupeZ(u8, output_slice);
        } else {
            return error.Pcre2Error;
        }
    }

    /// Docs: https://www.pcre.org/current/doc/html/pcre2api.html#SEC39
    pub fn dfaMatch(self: Matcher, string: []const u8, start_offset: ?usize) bool {
        const options: u32 = 0 | c.PCRE2_DFA_SHORTEST;
        const context: ?*c.pcre2_real_match_context_8 = null;

        const md: ?*c.pcre2_match_data_8 = c.pcre2_match_data_create_8(2, null);
        defer c.pcre2_match_data_free_8(md);

        var workspace: [std.fs.max_path_bytes * 2]c_int = undefined;

        const rc = c.pcre2_dfa_match_8(
            self.matcher,
            string.ptr,
            string.len,
            start_offset orelse 0,
            options,
            md,
            context,
            &workspace,
            workspace.len,
        );

        if (rc < 0) {
            var buffer: [1024 * 4]u8 = undefined;
            const err_msg = getErrorMessage(rc, &buffer);

            std.debug.print(
                "failed to match {s} with errorcode {} and message '{s}'\n",
                .{ string, rc, err_msg },
            );
        }

        return rc > 0;
    }
};

test "Matcher" {
    _ = Matcher;

    const matcher = try Matcher.compile(".*some literal\\w.*");
    defer matcher.free();

    const matches1 = matcher.dfaMatch("blah blah", null);
    try std.testing.expect(!matches1);

    const matches2 = matcher.dfaMatch("some text then some literals, man", null);
    try std.testing.expect(matches2);
}
