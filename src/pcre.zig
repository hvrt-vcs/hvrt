const std = @import("std");
const unicode = std.unicode;

const c = @import("c.zig").cnamespace;
const dir_walker = @import("dir_walker.zig");
const IgnorePattern = dir_walker.IgnorePattern;

const log = std.log.scoped(.pcre);

pub const Error = error{
    InvalidUtf8,
    Pcre2Error,
};

/// A basic wrapper around raw pcre2 API. See docs here:
/// https://www.pcre.org/current/doc/html/pcre2api.html
pub const Matcher = struct {
    // Eventually wrap allocator in a pcre2 context.
    // alloc: std.mem.Allocator,
    matcher: *c.pcre2_code_8,

    /// Must call `free` on returned object, or memory will be leaked.
    pub fn compile(regex: []const u8) Error!Matcher {
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
            var error_msg_buf: [128]u8 = undefined;
            const error_msg_final = getErrorMessage(errorcode, &error_msg_buf);
            log.debug(
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
        if (error_msg_size < 0) {
            // Either the given code is not an error, or the given buffer is too small
            return &.{};
        } else {
            const msg_size_cast = @as(usize, @intCast(error_msg_size));
            const error_msg_final = buffer[0..msg_size_cast :0];
            return error_msg_final;
        }
    }

    pub fn convertGlob(alloc: std.mem.Allocator, glob: []const u8) ![:0]u8 {
        const options: u32 = 0 | c.PCRE2_CONVERT_GLOB;
        var output_opt: [*c]u8 = null;
        var output_size: usize = 0;
        const context: ?*c.pcre2_convert_context_8 = c.pcre2_convert_context_create_8(null);
        defer c.pcre2_convert_context_free_8(context);

        const rcs = c.pcre2_set_glob_separator_8(context, '/');
        if (rcs != 0) unreachable;

        const rc = c.pcre2_pattern_convert_8(
            glob.ptr,
            glob.len,
            options,
            &output_opt,
            &output_size,
            context,
        );
        defer c.pcre2_converted_pattern_free_8(output_opt);

        if (rc != 0) {
            var error_msg_buf: [128]u8 = undefined;
            const error_msg_final = getErrorMessage(rc, &error_msg_buf);
            log.debug("Something went wrong with glob conversion: {s}\n", .{error_msg_final});
            return error.Pcre2Error;
        }

        if (output_opt) |output| {
            const output_slice = output[0..output_size];
            return try alloc.dupeZ(u8, output_slice);
        } else {
            return error.Pcre2Error;
        }
    }

    /// Docs: https://www.pcre.org/current/doc/html/pcre2api.html#SEC39
    pub fn dfaMatchBool(self: Matcher, string: []const u8, start_offset: ?usize) bool {
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
            var buffer: [128]u8 = undefined;
            const err_msg = getErrorMessage(rc, &buffer);

            log.debug(
                "failed to match {s} with errorcode {} and message '{s}'\n",
                .{ string, rc, err_msg },
            );
        }

        return rc > 0;
    }
};

test "Matcher.dfaMatch" {
    _ = Matcher;

    const matcher = try Matcher.compile(".*some literal\\w.*");
    defer matcher.free();

    const matches1 = matcher.dfaMatchBool("blah blah", null);
    try std.testing.expect(!matches1);

    const matches2 = matcher.dfaMatchBool("some text then some literals, man", null);
    try std.testing.expect(matches2);
}

test "Matcher.convertGlob" {
    _ = Matcher;

    const alloc = std.testing.allocator;

    const glob = "*.zig";
    const converted = try Matcher.convertGlob(alloc, glob);
    defer alloc.free(converted);

    log.debug(
        "\n\nWhat is the converted pattern? \"{s}\" -> \"{s}\"\n\n",
        .{ glob, converted },
    );

    const matcher = try Matcher.compile(converted);
    defer matcher.free();

    const matches1 = matcher.dfaMatchBool("blah blah", null);
    try std.testing.expect(!matches1);

    const matches2 = matcher.dfaMatchBool("src/add.zig", null);
    try std.testing.expect(!matches2);

    const matches3 = matcher.dfaMatchBool("add.zig", null);
    try std.testing.expect(matches3);
}

pub const FileIgnorer = struct {
    const MatcherMap = std.StringHashMap(Matcher);

    compiled_patterns: MatcherMap,

    pub fn init(alloc: std.mem.Allocator) !FileIgnorer {
        return .{
            .compiled_patterns = MatcherMap.init(alloc),
        };
    }

    pub fn deinit(self: *FileIgnorer) void {
        self.compiled_patterns.deinit();
    }

    pub fn fileIgnorer(self: *FileIgnorer) dir_walker.FileIgnorer {
        return .{
            .context = @ptrCast(self),
            .vtable = .{
                .put_patterns = put_patterns,
                .remove_patterns = remove_patterns,
                .is_ignored = is_ignored,
            },
        };
    }

    pub fn put_patterns(context: *anyopaque, relpath: []const u8, patterns: []IgnorePattern) anyerror!void {
        const self = @as(*FileIgnorer, @ptrCast(@alignCast(context)));
        _ = self; // autofix
        _ = patterns; // autofix
        _ = relpath; // autofix
    }

    pub fn remove_patterns(context: *anyopaque, relpath: []const u8) void {
        const self = @as(*FileIgnorer, @ptrCast(@alignCast(context)));
        _ = self; // autofix
        _ = relpath; // autofix
    }

    pub fn is_ignored(context: *anyopaque, relpath: []const u8) bool {
        const self = @as(*FileIgnorer, @ptrCast(@alignCast(context)));
        _ = self; // autofix
        _ = relpath; // autofix
        return false;
    }
};

test "refAllDeclsRecursive" {
    std.testing.refAllDeclsRecursive(@This());
}
