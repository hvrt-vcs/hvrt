const std = @import("std");
const fspath = std.fs.path;
const Dir = std.fs.Dir;

const log = std.log.scoped(.add);

const hvrt_dirname: [:0]const u8 = ".hvrt";
const work_tree_db_name: [:0]const u8 = "work_tree_state.sqlite";

pub const Value = std.json.Value;
const parseFromSliceLeaky = std.json.parseFromSliceLeaky;

pub const ConfigPairs = std.StringArrayHashMap(Value);

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

        var config_pairs = ConfigPairs.init(gpa);
        errdefer config_pairs.deinit();

        var spliterator = std.mem.splitScalar(u8, config, '\n');

        var line_count: usize = 1;
        while (spliterator.next()) |_| line_count += 1;
        try config_pairs.ensureTotalCapacity(line_count);

        spliterator.reset();

        var cur_line: usize = 0;
        while (spliterator.next()) |l| {
            cur_line += 1;
            const ltrimmed = std.mem.trimLeft(u8, l, " \t\r\n");

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
            const key = std.mem.trim(u8, padded_key, " \t\r\n");
            log.debug("Are we parsing the key correctly? \"{s}\"\n", .{key});

            // Value could be empty, so check for that
            const padded_value = if (ltrimmed[eql_idx..].len == 1) &.{} else ltrimmed[(eql_idx + 1)..];

            const map_val: Value = blk: {
                if (parseFromSliceLeaky(
                    Value,
                    arena_ptr.allocator(),
                    padded_value,
                    .{ .allocate = .alloc_if_needed },
                )) |p| {
                    break :blk p;
                } else |_| {
                    break :blk Value{ .string = padded_value };
                }
            };

            // Later entries in the config should overwrite earlier ones.
            config_pairs.putAssumeCapacity(key, map_val);
        }

        return .{
            .arena_ptr = arena_ptr,
            .config_pairs = config_pairs,
        };
    }

    pub fn deinit(self: *Self) void {
        self.config_pairs.deinit();

        const child_allocator = self.arena_ptr.child_allocator;
        self.arena_ptr.deinit();
        child_allocator.destroy(self.arena_ptr);
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
;

test Config {
    var config = try Config.parse(std.testing.allocator, test_config_good);
    defer config.deinit();

    try std.testing.expectEqual(5, config.config_pairs.count());

    var iterator = config.config_pairs.iterator();
    const first = iterator.next().?;
    try std.testing.expectEqualStrings("worktree.repo.type", first.key_ptr.*);

    const must_be_string = first.value_ptr.string;
    try std.testing.expectEqualStrings("sqlite", must_be_string);

    const second = iterator.next().?;
    const must_be_string2 = second.value_ptr.string;
    try std.testing.expectEqualStrings("file:.hvrt/repo.hvrt", must_be_string2);

    // according to the voll spec, the leading and trailing whitespace should
    // NOT be stripped by default from values that cannot trivially be treated
    // as JSON values.
    //
    // In essence, the whitespace padding below is expected.
    const third = iterator.next().?;
    const must_be_string3 = third.value_ptr.string;
    try std.testing.expectEqualStrings(" a bare value outside of quotes  ", must_be_string3);

    const fourth = iterator.next().?;
    const must_be_int = fourth.value_ptr.integer;
    try std.testing.expectEqual(123, must_be_int);

    const fifth = iterator.next().?;
    const must_be_float = fifth.value_ptr.float;
    try std.testing.expectApproxEqRel(
        2.0,
        must_be_float,
        std.math.sqrt(std.math.floatEps(f64)),
    );
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
