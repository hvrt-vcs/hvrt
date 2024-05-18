const std = @import("std");
const c = @import("c.zig");
const utf = std.unicode;

/// A basic wrapper around raw pcre2 API. See docs here:
/// https://www.pcre.org/current/doc/html/pcre2api.html
pub const Matcher = struct {
    // Eventually wrap allocator in a pcre2 context.
    alloc: std.mem.Allocator,
    matcher: *c.pcre2_code_8,

    /// Must call `free` on returned object, or memory will be leaked.
    pub fn compile(alloc: std.mem.Allocator, regex: []const u8) !Matcher {
        const options: u32 = 0;
        var errorcode: c_int = 0;
        var erroroffset: usize = 0;
        const context: ?*c.pcre2_compile_context_8 = null;
        var error_msg_buf: [1024 * 4]u8 = undefined;

        const matcher_opt = c.pcre2_compile_8(regex.ptr, regex.len, options, &errorcode, &erroroffset, context);

        if (matcher_opt) |matcher| {
            return .{ .matcher = matcher, .alloc = alloc };
        } else {
            const error_msg_size = c.pcre2_get_error_message_8(errorcode.*, &error_msg_buf, error_msg_buf.len);
            const error_msg_final = error_msg_buf[0..error_msg_size];
            std.debug.print(
                "Regex '{s}' failed to compile with errorcode {} at offset {} with message '{s}'",
                .{ regex, errorcode.*, erroroffset.*, error_msg_final },
            );
            return error.Pcre2Error;
        }
    }

    pub fn free(self: Matcher) void {
        c.pcre2_code_free_8(self.matcher);
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

    const matches = matcher.dfaMatch("blah blah", null);

    try std.testing.expect(matches);
}
