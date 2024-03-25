//! Core Data structures are kept here. These are mostly the high level
//! abstraction for the parts that are hashed into the merkle. For data
//! structures that are merely implementation details (i.e. not hashed into the
//! merkle tree), see the `impl.zig` file in the same directory.
//!
//! We use slices with a null sentinel throughout the data structures primarily
//! because we need to interoperate with SQLite and other C code a lot, and
//! forcing the sentinel to always be there from the beginning makes interop
//! easier.

const std = @import("std");
const log = std.log.scoped(.ds);

const testing = std.testing;

pub const HashAlgo = enum {
    sha3_256,
    sha1, // for interop with git, maybe?
};

pub fn hashAlgoEnumToType(comptime hash_algo: HashAlgo) type {
    return switch (hash_algo) {
        .sha3_256 => std.crypto.hash.sha3.Sha3_256,
        .sha1 => std.crypto.hash.Sha1,
    };
}

test "test hashAlgoEnumToType" {
    const sha3_type = hashAlgoEnumToType(.sha3_256);
    try testing.expectEqual(std.crypto.hash.sha3.Sha3_256, sha3_type);
}

pub const ParentType = enum {
    regular,
    merge,
    cherry_pick,
    revert,
};

pub const HashKey = struct {
    pub const hash_key_sep: [:0]const u8 = "|";

    hash: [:0]const u8,
    hash_algo: HashAlgo,

    pub fn equal(self: HashKey, other: HashKey) bool {
        return self.hash_algo == other.hash_algo and std.mem.eql(u8, self.hash, other.hash);
    }

    pub fn toString(self: HashKey, alloc: std.mem.Allocator) ![:0]u8 {
        const parts = [_][]const u8{ @tagName(self.hash_algo), self.hash };
        return try std.mem.joinZ(alloc, hash_key_sep, &parts);
    }
};

test "HashKey toString" {
    const hk = HashKey{ .hash = "deadbeef", .hash_algo = .sha3_256 };

    const hks = try hk.toString(testing.allocator);
    defer testing.allocator.free(hks);

    const expected = "sha3_256|deadbeef";
    try testing.expect(std.mem.eql(u8, expected, hks));
}

pub const StringMap = std.StringHashMap([]const u8);

pub const Headers = struct {
    const illegal_header_chars: [:0]const u8 = "=\n";

    alloc: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    arena_alloc: std.mem.Allocator,
    header_map: StringMap,

    pub fn init(alloc: std.mem.Allocator) Headers {
        var arena = std.heap.ArenaAllocator.init(alloc);
        return .{
            .alloc = alloc,
            .arena = arena,
            .arena_alloc = arena.allocator(),
            .header_map = StringMap.init(alloc),
        };
    }

    pub fn deinit(self: *Headers) void {
        self.header_map.deinit();
        self.arena.deinit();
        // self.* = undefined;
    }

    pub fn toString(self: Headers, alloc: std.mem.Allocator) ![:0]u8 {
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        var arena_alloc = arena.allocator();

        var keys = std.ArrayList([]const u8).init(arena_alloc);
        defer keys.deinit();

        var key_iter = self.header_map.keyIterator();
        while (key_iter.next()) |k| {
            try keys.append(k.*);
        }
        std.sort.insertion([]const u8, keys.items, self, Headers.lessThanCmp);

        var final_string = std.ArrayList(u8).init(arena_alloc);
        defer final_string.deinit();

        for (keys.items) |key| {
            const value = self.header_map.get(key) orelse "";
            const line = try std.fmt.allocPrint(arena_alloc, "{s}={s}\n", .{ key, value });
            try final_string.appendSlice(line);
        }
        return try alloc.dupeZ(u8, final_string.items);
    }

    fn lessThanCmp(_: Headers, lhs: []const u8, rhs: []const u8) bool {
        return std.mem.lessThan(u8, lhs, rhs);
    }

    /// Return `true` if header was inserted, false otherwise. Allocation
    /// errors are bubbled up.
    pub fn insertHeader(self: *Headers, key: []const u8, value: []const u8) !bool {
        if (std.mem.indexOfAny(u8, key, illegal_header_chars)) |idx| {
            log.err("Key \'{s}\' contains illegal character: {c}", .{ key, key[idx] });
            return error.IllegalHeaderChar;
        } else if (std.mem.indexOfAny(u8, value, illegal_header_chars)) |idx| {
            log.err("value \'{s}\' contains illegal character: {c}", .{ value, value[idx] });
            return error.IllegalHeaderChar;
        }

        if (self.header_map.get(key)) |v| {
            log.err("Key '{s}' already exists in headers with value '{s}'", .{ key, v });
            return false;
        } else {
            const key_copy = try self.arena_alloc.dupeZ(u8, key);
            const value_copy = try self.arena_alloc.dupeZ(u8, value);
            try self.header_map.put(key_copy, value_copy);
            return true;
        }
    }

    /// Returned value is owned by the internal arena allocator inside the
    /// Header object. Once this object is deinit'd, the value will no longer
    /// be valid.
    pub fn popHeader(self: *Headers, key: []const u8) ?[]const u8 {
        return if (self.header_map.fetchRemove(key)) |kv| kv.value else null;
    }
};

test "Headers.toString" {
    var test_headers = Headers.init(testing.allocator);
    defer test_headers.deinit();

    // FIXME: test runner sees a memory leak here for some reason.
    try testing.expect(try test_headers.insertHeader("some_key", "some_value") == true);
    try testing.expect(try test_headers.insertHeader("another_key", "another_value") == true);

    // second attempt to insert same key should fail
    try testing.expect(try test_headers.insertHeader("some_key", "some_different_value") == false);

    const final_string1 = try test_headers.toString(testing.allocator);
    defer testing.allocator.free(final_string1);
    try testing.expect(std.mem.eql(u8, final_string1, "another_key=another_value\nsome_key=some_value\n"));

    try testing.expect(std.mem.eql(u8, test_headers.popHeader("some_key").?, "some_value"));

    const final_string2 = try test_headers.toString(testing.allocator);
    defer testing.allocator.free(final_string2);

    std.debug.print("\n\nWhat is final_string2? {s}\n\n", .{final_string2});
    try testing.expect(std.mem.eql(u8, final_string2, "another_key=another_value\n"));
}

pub const Commit = struct {
    hash_key: HashKey,
    headers: Headers,
    parent_edges: []*CommitParent,
    tree: *Tree,

    /// A Commit object doesn't "own" anything and does not need to be deinit'd directly.
    pub fn init(hash_key: HashKey, headers: Headers, parent_edges: []*CommitParent, tree: *Tree) !Commit {
        return .{
            .hash_key = hash_key,
            .headers = headers,
            .parent_edges = parent_edges,
            .tree = tree,
        };
    }

    /// Hash a commit without actually having a Commit object built yet.
    pub fn nakedHash(alloc: std.mem.Allocator, parent_edges: []*CommitParent, tree: *Tree, headers: Headers) !HashKey {
        const Temp = Commit{
            .hash_key = undefined,
            .headers = headers,
            .parent_edges = parent_edges,
            .tree = tree,
        };

        return try Temp.hash(alloc);
    }

    /// Don't pass in an Arena here. A lot of intermediate memory is allocated
    /// that is simply thrown away. This method should be cleaned up, in that
    /// sense.
    pub fn hash(self: Commit, alloc: std.mem.Allocator) !HashKey {
        var hasher = std.crypto.hash.sha3.Sha3_256.init(.{});
        var writer = hasher.writer();

        var header_lines_builder = std.ArrayList(u8).init(alloc);
        defer header_lines_builder.deinit();

        var parent_hashes_builder = std.ArrayList(u8).init(alloc);
        defer parent_hashes_builder.deinit();

        const header_lines: [:0]const u8 = try header_lines_builder.toOwnedSliceSentinel(0);
        defer alloc.free(header_lines);

        const parent_hashes: [:0]const u8 = try parent_hashes_builder.toOwnedSliceSentinel(0);
        defer alloc.free(parent_hashes);

        const hashables = .{
            parent_hashes,
            self.tree.toString(),
            header_lines,
        };

        for (hashables) |h| {
            // since hasher.update cannot return an error, this writer cannot
            // return an error either.
            writer.print("{s}\n", .{h}) catch unreachable;
        }

        var digest: [std.crypto.hash.sha3.Sha3_256.digest_length]u8 = undefined;

        hasher.final(&digest);

        const hex_digest = std.fmt.bytesToHex(digest, .lower);
        const hex_digestz = alloc.dupeZ(u8, hex_digest);

        return .{
            .hash = hex_digestz,
            .hash_algo = .sha3_256,
        };
    }

    pub fn confirmHash(self: Commit) bool {
        return self.hash_key.equal(self.hash());
    }

    pub fn toString(self: *Commit, alloc: std.mem.Allocator) ![:0]u8 {
        _ = self;

        var return_value = try alloc.dupeZ(u8, "something, something");

        return return_value;
    }
};

pub const CommitParent = struct {
    commit: *Commit,
    ptype: ParentType,
};

pub const Tree = struct {
    tree_entries: []*TreeEntry,

    pub fn toString(self: Tree, alloc: std.mem.Allocator) ![:0]u8 {
        _ = self;

        var final_value = try alloc.dupeZ(u8, "");
        return final_value;
    }
};

pub const TreeEntry = struct {
    file_id: *FileId,
    blob: *Blob,
};

pub const FileId = struct {
    hash_key: HashKey,
    path: [:0]const u8,
    parents: []*FileId,
};

pub const Blob = struct {
    hash_key: HashKey,
};
