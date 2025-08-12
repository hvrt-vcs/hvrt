const std = @import("std");
const fspath = std.fs.path;
const Dir = std.fs.Dir;
const json = std.json;

const log = std.log.scoped(.add);

const hvrt_dirname: [:0]const u8 = ".hvrt";
const work_tree_db_name: [:0]const u8 = "work_tree_state.sqlite";

const whitespace = " \t\r\n";

pub const Value = struct {
    const Self = @This();

    raw: []const u8,

    pub fn eql(a: Self, b: Self) bool {
        return std.mem.eql(u8, a.raw, b.raw);
    }

    pub fn trimWhitespace(self: Self) Self {
        return .{ .raw = std.mem.trim(u8, self.raw, whitespace) };
    }

    pub fn isEmpty(self: Self) bool {
        return self.trimWhitespace().raw.len == 0;
    }

    /// Checks for a pair of chars, if present. The internal raw slice must
    /// *not* be padded with whitespace. The chars *must* be the first and last
    /// characters of the internal slice.
    fn hasSurroundingChars(self: Self, first: u8, last: u8) bool {
        // len of 0 means empty string. len of 1 means there aren't at least two
        // characters to strip.
        if (self.raw.len <= 1) {
            return false;
        } else if (self.raw[0] != first) {
            return false;
        } else if (self.raw[self.raw.len - 1] != last) {
            return false;
        } else {
            return true;
        }
    }

    /// Strip a pair of chars, if both are present.
    fn trimSurroundingChars(self: Self, first: u8, last: u8) Self {
        if (self.hasSurroundingChars(first, last)) {
            const trimmed = self.raw[1..(self.raw.len - 1)];
            return .{ .raw = trimmed };
        } else {
            return self;
        }
    }

    /// Checks for a pair of double quotes, if present.
    pub fn hasDoubleQuotes(self: Self) bool {
        return self.hasSurroundingChars('"', '"');
    }

    /// Strip a pair of double quotes, if present.
    pub fn trimDoubleQuotes(self: Self) Self {
        return self.trimSurroundingChars('"', '"');
    }

    pub fn parseAsJson(self: Self, arena: std.mem.Allocator) !json.Value {
        return try json.parseFromSliceLeaky(
            json.Value,
            arena,
            self.raw,
            .{ .allocate = .alloc_if_needed },
        );
    }

    /// Returns `error.UnexpectedToken` when it encounters a JSON array or a
    /// JSON object. Otherwise, behaves the same as `parseAsJson`.
    pub fn parseAsJsonScalar(self: Self, arena: std.mem.Allocator) !json.Value {
        // This matches the error that the JSON library returns.
        const scalar_error = error.UnexpectedToken;

        // Don't waste time parsing arrays or objects.
        // If either seems present, fail early.
        const trimmed = self.trimWhitespace().raw;
        if (trimmed.len > 0 and (trimmed[0] == '[' or trimmed[0] == '{')) {
            return scalar_error;
        }

        const parsed = try self.parseAsJson(arena);

        return parsed;
    }

    const parseFromSliceLeaky = std.json.parseFromSliceLeaky;
};

pub const ValueList = std.ArrayList(Value);
pub const ConfigPairs = std.StringArrayHashMap(ValueList);

pub const Config = struct {
    const Self = @This();
    arena_ptr: *std.heap.ArenaAllocator,
    config_pairs: ConfigPairs,

    /// The Config return object creates slices that reference subslices of the
    /// passed in `config` variable. This value should not be deallocated
    /// before the `Config` object has `deinit` called on it.
    pub fn parse(gpa: std.mem.Allocator, config: []const u8) !Config {
        const arena_ptr = try gpa.create(std.heap.ArenaAllocator);
        errdefer gpa.destroy(arena_ptr);

        arena_ptr.* = std.heap.ArenaAllocator.init(gpa);
        errdefer arena_ptr.deinit();

        const arena = arena_ptr.allocator();
        var config_pairs = ConfigPairs.init(arena);
        var spliterator = std.mem.splitScalar(u8, config, '\n');

        var line_count: usize = 1;
        while (spliterator.next()) |_| line_count += 1;
        try config_pairs.ensureTotalCapacity(line_count);

        spliterator.reset();

        var cur_line: usize = 0;
        while (spliterator.next()) |l| {
            cur_line += 1;
            const ltrimmed = std.mem.trimLeft(u8, l, whitespace);

            // Empty line
            if (ltrimmed.len == 0) continue;

            // Comment line
            if (ltrimmed[0] == '#') continue;

            const eql_idx = std.mem.indexOfScalar(u8, ltrimmed, '=') orelse {
                log.warn("Line {any} of config is invalid: \"{s}\" \n", .{ cur_line, l });
                return error.InvalidConfig;
            };

            // FIXME: validate that `key` is a valid voll key. Currently, it
            // could be anything that isn't whitesapce or the equals sign.
            const padded_key = ltrimmed[0..eql_idx];
            log.debug("Are we parsing the padded key correctly? \"{s}\"\n", .{padded_key});
            const key = std.mem.trim(u8, padded_key, whitespace);
            log.debug("Are we parsing the key correctly? \"{s}\"\n", .{key});

            // Value could be empty, so check for that
            const padded_value = if (ltrimmed[eql_idx..].len == 1) &.{} else ltrimmed[(eql_idx + 1)..];

            const map_val: Value = .{ .raw = padded_value };

            // Hold on to all declarations of a config value.
            if (config_pairs.getEntry(key)) |e| {
                try e.value_ptr.append(map_val);
            } else {
                var value_list = ValueList.init(arena);
                try value_list.append(map_val);
                config_pairs.putAssumeCapacity(key, value_list);
            }
        }

        return .{
            .arena_ptr = arena_ptr,
            .config_pairs = config_pairs,
        };
    }

    pub fn deinit(self: *Self) void {
        const child_allocator = self.arena_ptr.child_allocator;
        self.arena_ptr.deinit();
        child_allocator.destroy(self.arena_ptr);
    }

    /// Get the last declaration of the config value by the given config key.
    ///
    /// Return `null` if config by that key cannot be found.
    pub fn get(self: Self, key: []const u8) ?Value {
        if (self.config_pairs.getEntry(key)) |e| {
            return e.value_ptr.getLast();
        } else {
            return null;
        }
    }

    /// Get values from all declaration of the config value by the given config key.
    ///
    /// Return `null` if config by that key cannot be found.
    pub fn getAll(self: Self, key: []const u8) ?ValueList {
        if (self.config_pairs.getEntry(key)) |e| {
            return e.value_ptr.*;
        } else {
            return null;
        }
    }
};

const test_config_good =
    \\ # Start with a comment.
    \\ worktree.repo.type = "sqlite"
    \\
    \\ # some blank lines.
    \\
    \\
    \\ worktree.repo.uri = "file:.hvrt/repo.hvrt"
    \\
    \\
    \\ # Another comment.
    \\
    \\ some.fake.key = a bare value outside of quotes  
    \\ some.fake.key2 = 123
    \\ some.fake.key3 = 2.0
    \\
    \\ a.valid.json.object = {"key": "value"}
    \\ a.valid.json.array = ["value1", "value2"]
;

test Config {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var config = try Config.parse(std.testing.allocator, test_config_good);
    defer config.deinit();

    try std.testing.expectEqual(7, config.config_pairs.count());

    const as_json1 = try config.get("worktree.repo.type").?.parseAsJsonScalar(arena);
    try std.testing.expectEqualStrings("sqlite", as_json1.string);

    const as_json2 = try config.get("worktree.repo.uri").?.parseAsJsonScalar(arena);
    const must_be_string2 = as_json2.string;
    try std.testing.expectEqualStrings("file:.hvrt/repo.hvrt", must_be_string2);

    // according to the voll spec, the leading and trailing whitespace MUST
    // NOT be stripped by default from values that cannot trivially be treated
    // as JSON values.
    //
    // In essence, the whitespace padding below is expected.
    const value3 = config.get("some.fake.key") orelse return error.MissingKey;
    const as_json3 = value3.parseAsJsonScalar(arena);
    try std.testing.expectError(error.SyntaxError, as_json3);
    const must_be_string3 = value3.raw;
    try std.testing.expectEqualStrings(" a bare value outside of quotes  ", must_be_string3);
    try std.testing.expectEqualStrings("a bare value outside of quotes", value3.trimWhitespace().raw);

    const value4 = config.get("some.fake.key2") orelse return error.MissingKey;
    const as_json4 = try value4.parseAsJsonScalar(arena);
    const must_be_int = as_json4.integer;
    try std.testing.expectEqual(123, must_be_int);

    const value5 = config.get("some.fake.key3") orelse return error.MissingKey;
    const as_json5 = try value5.parseAsJsonScalar(arena);
    const must_be_float = as_json5.float;
    try std.testing.expectApproxEqRel(
        2.0,
        must_be_float,
        std.math.sqrt(std.math.floatEps(f64)),
    );

    const value6 = config.get("a.valid.json.object") orelse return error.MissingKey;
    // This should succeed
    _ = try value6.parseAsJson(arena);
    // This should fail
    const as_json6 = value6.parseAsJsonScalar(arena);
    try std.testing.expectError(error.UnexpectedToken, as_json6);
    const must_be_string6 = value6.trimWhitespace().raw;
    try std.testing.expectEqualStrings("{\"key\": \"value\"}", must_be_string6);

    const value7 = config.get("a.valid.json.array") orelse return error.MissingKey;
    // This should succeed
    _ = try value7.parseAsJson(arena);
    // This should fail
    const as_json7 = value7.parseAsJsonScalar(arena);
    try std.testing.expectError(error.UnexpectedToken, as_json7);
    const must_be_string7 = value7.trimWhitespace().raw;
    try std.testing.expectEqualStrings("[\"value1\", \"value2\"]", must_be_string7);
}

// // FIXME: "refAllDeclsRecursive" throws an error for some reason.
// test "refAllDeclsRecursive" {
//     std.debug.print("Starting refAllDeclsRecursive d\n\n", .{});
//     std.testing.refAllDeclsRecursive(@This());
// }

test "url parse" {
    const uri_string = "file:.hvrt/repo.hvrt";

    const uri = try std.Uri.parse(uri_string);

    // std.debug.print("What is the uri scheme? {s}\n\n", .{uri.scheme});
    // std.debug.print("What is the uri path? {any}\n\n", .{uri.path});

    const path = switch (uri.path) {
        .raw => |v| v,
        .percent_encoded => |v| v,
    };

    try std.testing.expectEqualStrings("file", uri.scheme);
    try std.testing.expectEqualStrings(".hvrt/repo.hvrt", path);
    try std.testing.expectEqual(null, uri.host);
}
