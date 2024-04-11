//! Core Data structures are kept here. These are mostly the high level
//! abstraction for the parts that are hashed into the merkle tree. For data
//! structures that are merely implementation details (i.e. not hashed into the
//! merkle tree), see the `impl.zig` file in the same directory.
//!
//! We use slices with a null sentinel throughout the data structures primarily
//! because we need to interoperate with SQLite and other C code a lot, and
//! forcing the sentinel to always be there from the beginning makes interop
//! easier.

const std = @import("std");
const log = std.log.scoped(.ds_core);
const Order = std.math.Order;

const assert = std.debug.assert;

const testing = std.testing;

// TODO: convert all object pointers into HashKey objects. These can then be
// used to point into HashMaps holding the actual objects.
pub const CommitHashMap = std.HashMap(HashKey, Commit, HashKey.HashMapContext, 80);
pub const TreeHashMap = std.HashMap(HashKey, Tree, HashKey.HashMapContext, 80);
pub const FileIdHashMap = std.HashMap(HashKey, FileId, HashKey.HashMapContext, 80);
pub const BlobHashMap = std.HashMap(HashKey, Blob, HashKey.HashMapContext, 80);

var fifo = std.fifo.LinearFifo(u8, .{ .Static = 1024 * 4 }).init();

pub const HashAlgo = enum {
    sha1, // for interop with git, maybe?
    sha3_256,

    pub const default = .sha3_256;

    pub fn HasherType(comptime hash_algo: HashAlgo) type {
        return switch (hash_algo) {
            .sha1 => std.crypto.hash.Sha1,
            .sha3_256 => std.crypto.hash.sha3.Sha3_256,
        };
    }

    fn fromReaderComptime(comptime hash_algo: HashAlgo, alloc: std.mem.Allocator, reader: anytype) ![:0]u8 {
        const hasher_type = hash_algo.HasherType();
        var hasher = hasher_type.init(.{});

        try fifo.pump(reader, hasher.writer());

        var digest_buf: [hasher_type.digest_length]u8 = undefined;
        hasher.final(&digest_buf);
        var file_digest_hex = std.fmt.bytesToHex(digest_buf, .lower);
        return try alloc.dupeZ(u8, &file_digest_hex);
    }

    /// Allocator is used to allocate the hash string. Caller is responsible
    /// for releasing the memory on the returned string.
    pub fn fromReader(hash_algo: HashAlgo, alloc: std.mem.Allocator, reader: anytype) ![:0]u8 {
        return switch (hash_algo) {
            .sha1 => try HashAlgo.fromReaderComptime(.sha1, alloc, reader),
            .sha3_256 => try HashAlgo.fromReaderComptime(.sha3_256, alloc, reader),
        };
    }

    /// Convenience method to wrap in memory buffer in a
    /// `std.io.FixedBufferStream`, then call `fromReader`.
    pub fn fromBuffer(hash_algo: HashAlgo, alloc: std.mem.Allocator, buffer: anytype) ![:0]u8 {
        var buf_stream = std.io.fixedBufferStream(buffer);
        var reader = buf_stream.reader();

        return try hash_algo.fromReader(alloc, reader);
    }
};

test "HashAlgo.toType" {
    const sha3_type = HashAlgo.HasherType(.sha3_256);
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

    /// The allocator that originally allocated the hash string. If not
    /// present, will not be used during deinit.
    alloc_opt: ?std.mem.Allocator = null,
    hash: [:0]const u8,
    hash_algo: HashAlgo = HashAlgo.default,

    pub const HashMapContext = struct {
        const Self = @This();

        pub fn hash(_: Self, a: HashKey) u64 {
            var final_hash: u64 = 0;
            for (@tagName(a.hash_algo)) |byte| final_hash = final_hash +% byte;
            for (a.hash) |byte| final_hash = final_hash +% byte;
            return final_hash;
        }

        pub fn eql(_: Self, a: HashKey, b: HashKey) bool {
            return a.hash_algo == b.hash_algo and std.mem.eql(u8, a, b);
        }
    };

    pub fn deinit(self: *const HashKey) void {
        if (self.alloc_opt) |alloc| {
            alloc.free(self.hash);
        }
    }

    /// Allocator is used to allocate the internal hash string. Caller is
    /// responsible for releasing the memory by calling `deinit()` on the
    /// returned `HashKey` object.
    ///
    /// If you do not want to initialize from a reader-like object and/or call
    /// `deinit`, then create a HashKey directly with struct literal syntax and
    /// be certain to release hash string memory elsewhere.
    pub fn init(hash_algo: HashAlgo, alloc: std.mem.Allocator, reader: anytype) !HashKey {
        const file_digest_hexz = try hash_algo.fromReader(alloc, reader);

        return .{
            .alloc_opt = alloc,
            .hash = file_digest_hexz,
            .hash_algo = hash_algo,
        };
    }

    pub fn equal(self: *const HashKey, other: *const HashKey) bool {
        return self.hash_algo == other.hash_algo and std.mem.eql(u8, self.hash, other.hash);
    }

    pub fn toString(self: *const HashKey, alloc: std.mem.Allocator) ![:0]u8 {
        const parts = [_][]const u8{ @tagName(self.hash_algo), self.hash };
        return try std.mem.joinZ(alloc, hash_key_sep, &parts);
    }

    pub fn fmtToString(self: *const HashKey, alloc: std.mem.Allocator, parts: anytype) ![:0]u8 {
        const all_parts = parts ++ [_][]const u8{ @tagName(self.hash_algo), self.hash };
        return try std.mem.joinZ(alloc, hash_key_sep, &all_parts);
    }
};

test "HashKey.fmtToString" {
    const hk = HashKey{
        .hash = "4852f4770df7e88b3f383688d6163bfb0a8fef59dc397efcb067e831b533f08e",
        .hash_algo = .sha3_256,
    };
    const expected = "typename|sha3_256|4852f4770df7e88b3f383688d6163bfb0a8fef59dc397efcb067e831b533f08e";

    const hks = try hk.fmtToString(testing.allocator, .{"typename"});
    defer testing.allocator.free(hks);

    try testing.expect(std.mem.eql(u8, expected, hks));
}

test "HashKey.toString" {
    const hk = HashKey{
        .hash = "4852f4770df7e88b3f383688d6163bfb0a8fef59dc397efcb067e831b533f08e",
        .hash_algo = .sha3_256,
    };
    const expected = "sha3_256|4852f4770df7e88b3f383688d6163bfb0a8fef59dc397efcb067e831b533f08e";

    const hks = try hk.toString(testing.allocator);
    defer testing.allocator.free(hks);

    try testing.expect(std.mem.eql(u8, expected, hks));
}

test "HashKey.fromReader" {
    const to_hash = "deadbeef";
    const expected_hash: [:0]const u8 = "4852f4770df7e88b3f383688d6163bfb0a8fef59dc397efcb067e831b533f08e";

    var buf_stream = std.io.fixedBufferStream(to_hash);
    var reader = buf_stream.reader();

    // declare as var to force runtime evaluation
    var hash_algo: HashAlgo = undefined;
    hash_algo = .sha3_256;

    const actual = try HashKey.init(hash_algo, testing.allocator, reader);
    defer actual.deinit();

    try testing.expectEqual(HashAlgo.sha3_256, actual.hash_algo);
    try testing.expect(std.mem.eql(u8, expected_hash, actual.hash));
}

// SHA1 should not ever actually be used in practice, but this is good as an
// example case of using an alternative hash algorithm.
test "HashKey.fromReader SHA1" {
    const to_hash = "deadbeef";
    const expected_hash: [:0]const u8 = "f49cf6381e322b147053b74e4500af8533ac1e4c";

    var buf_stream = std.io.fixedBufferStream(to_hash);
    var reader = buf_stream.reader();

    // declare as var to force runtime evaluation
    var hash_algo: HashAlgo = undefined;
    hash_algo = .sha1;

    const actual = try HashKey.init(hash_algo, testing.allocator, reader);
    defer actual.deinit();

    try testing.expectEqual(HashAlgo.sha1, actual.hash_algo);
    try testing.expect(std.mem.eql(u8, expected_hash, actual.hash));
}

pub const StringMap = std.StringHashMap([]const u8);

pub const Headers = struct {
    const illegal_header_chars: [:0]const u8 = "=\n";

    alloc: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    arena_alloc: std.mem.Allocator,
    header_map: StringMap,

    pub fn init(alloc: std.mem.Allocator) !Headers {
        var arena = try alloc.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(alloc);

        return .{
            .alloc = alloc,
            .arena = arena,
            .arena_alloc = arena.allocator(),
            .header_map = StringMap.init(alloc),
        };
    }

    /// deinit internal StringMap and ArenaAllocator.
    pub fn deinit(self: *Headers) void {
        self.arena.deinit();
        self.alloc.destroy(self.arena);
        self.header_map.deinit();
        self.* = undefined;
    }

    pub fn toString(self: *Headers, alloc: std.mem.Allocator) ![:0]u8 {
        var key_pq = std.PriorityQueue([]const u8, *Headers, Headers.lessThanCmpOrder).init(alloc, self);
        defer key_pq.deinit();

        var key_iter = self.header_map.keyIterator();
        while (key_iter.next()) |k| {
            try key_pq.add(k.*);
        }

        var final_string = std.ArrayList(u8).init(alloc);
        defer final_string.deinit();

        while (key_pq.removeOrNull()) |key| {
            const value = self.header_map.get(key) orelse "";
            const line = try std.fmt.allocPrint(alloc, "{s}={s}\n", .{ key, value });
            defer alloc.free(line);
            try final_string.appendSlice(line);
        }

        return try alloc.dupeZ(u8, final_string.items);
    }

    fn lessThanCmpOrder(_: *Headers, lhs: []const u8, rhs: []const u8) Order {
        if (std.mem.eql(u8, lhs, rhs)) {
            return Order.eq;
        } else if (std.mem.lessThan(u8, lhs, rhs)) {
            return Order.lt;
        } else {
            return Order.gt;
        }
    }

    /// Return `true` if header was inserted, false otherwise. Allocation
    /// errors are bubbled up.
    ///
    /// FIXME: printing a newline (`\n`) inside the log formats with a true
    /// newline. Needs to be be escaped before printing.
    pub fn insertHeader(self: *Headers, key: []const u8, value: []const u8) !bool {
        if (std.mem.indexOfAny(u8, key, illegal_header_chars)) |idx| {
            log.warn("Key \'{s}\' contains illegal character '{c}' at index {any}", .{ key, key[idx], idx });
            return error.IllegalHeaderChar;
        } else if (std.mem.indexOfAny(u8, value, illegal_header_chars)) |idx| {
            log.warn("value \'{s}\' contains illegal character '{c}' at index {any}", .{ value, value[idx], idx });
            return error.IllegalHeaderChar;
        }

        if (self.header_map.get(key)) |existing_value| {
            log.warn("Key '{s}' already exists in headers with value '{s}'", .{ key, existing_value });
            return false;
        } else {
            const key_copy = try self.arena_alloc.dupe(u8, key);
            const value_copy = try self.arena_alloc.dupe(u8, value);
            try self.header_map.put(key_copy, value_copy);
            return true;
        }
    }

    /// Returned value is owned by the internal arena allocator inside the
    /// Header object. Once deinit is called on the arena, this value will no
    /// longer point to valid memory.
    pub fn popHeader(self: *Headers, key: []const u8) ?[]const u8 {
        return if (self.header_map.fetchRemove(key)) |kv| kv.value else null;
    }
};

test "Headers.toString" {
    var test_headers = try Headers.init(testing.allocator);
    defer test_headers.deinit();

    try testing.expect(try test_headers.insertHeader("some_key", "some_value") == true);
    try testing.expect(try test_headers.insertHeader("zee_last_key", "zee_last_value") == true);
    try testing.expect(try test_headers.insertHeader("another_key", "another_value") == true);

    // second attempt to insert same key should fail
    try testing.expect(try test_headers.insertHeader("some_key", "some_different_value") == false);

    const final_string1 = try test_headers.toString(testing.allocator);
    defer testing.allocator.free(final_string1);
    try testing.expectEqualSlices(u8, final_string1, "another_key=another_value\nsome_key=some_value\nzee_last_key=zee_last_value\n");

    try testing.expectEqualSlices(u8, test_headers.popHeader("some_key").?, "some_value");
    try testing.expectEqual(test_headers.popHeader("some_key"), null);

    const final_string2 = try test_headers.toString(testing.allocator);
    defer testing.allocator.free(final_string2);

    try testing.expectEqualSlices(u8, final_string2, "another_key=another_value\nzee_last_key=zee_last_value\n");

    try testing.expect(try test_headers.insertHeader("some_key", "some_different_value") == true);

    const final_string3 = try test_headers.toString(testing.allocator);
    defer testing.allocator.free(final_string3);

    try testing.expectEqualSlices(u8, final_string3, "another_key=another_value\nsome_key=some_different_value\nzee_last_key=zee_last_value\n");

    const kerr = test_headers.insertHeader("bad=embedded=char", "doesn't matter");
    try testing.expectError(error.IllegalHeaderChar, kerr);

    const verr = test_headers.insertHeader("good_key", "bad\nvalue");
    try testing.expectError(error.IllegalHeaderChar, verr);
}

pub const Commit = struct {
    hash_key: HashKey,
    headers: Headers,
    parent_edges: []CommitParent,
    tree: HashKey,

    pub fn deinit(self: *Commit) void {
        self.hash_key.deinit();
        self.headers.deinit();
        self.* = undefined;
    }

    pub fn nakedInit(alloc: std.mem.Allocator, hash_algo: ?HashAlgo, parent_edges: []CommitParent, tree: HashKey, headers: Headers) !Commit {
        var hash_key = try Commit.nakedHash(alloc, hash_algo, parent_edges, tree, headers);

        return .{
            .hash_key = hash_key,
            .headers = headers,
            .parent_edges = parent_edges,
            .tree = tree,
        };
    }

    /// Hash a commit without actually having a Commit object built yet.
    pub fn nakedHash(alloc: std.mem.Allocator, hash_algo: ?HashAlgo, parent_edges: []CommitParent, tree: *Tree, headers: Headers) !HashKey {
        const final_algo = hash_algo orelse HashAlgo.default;
        const Temp = Commit{
            .hash_key = undefined,
            .headers = headers,
            .parent_edges = parent_edges,
            .tree = tree,
        };

        return try Temp.hash(alloc, final_algo);
    }

    /// Don't pass in an ArenaAllocator here if the result will be long lived.
    /// A lot of intermediate memory is allocated that is simply thrown away.
    pub fn hash(self: Commit, alloc: std.mem.Allocator, hash_algo: HashAlgo) !HashKey {
        var bytes_builder = std.ArrayList(u8).init(alloc);
        defer bytes_builder.deinit();

        // add header lines
        const header_string = try self.headers.toString(alloc);
        defer alloc.free(header_string);
        try bytes_builder.appendSlice(header_string);

        // TODO: add parent commit hashes
        for (self.parent_edges) |pe| {
            _ = pe;
        }

        // add tree hash
        const tree_string = try self.tree.toString(alloc);
        defer alloc.free(tree_string);
        try bytes_builder.appendSlice(tree_string);

        const hash_buf: []const u8 = bytes_builder.items;
        var buf_stream = std.io.fixedBufferStream(hash_buf);
        var reader = buf_stream.reader();

        return try HashKey.init(hash_algo, alloc, reader);
    }

    pub fn confirmHash(self: Commit, alloc: std.mem.Allocator) bool {
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        var arena_alloc = arena.allocator();

        var rehash_self = try self.hash(arena_alloc, self.hash_key.hash_algo);
        return self.hash_key.equal(rehash_self);
    }

    pub fn toString(self: *Commit, alloc: std.mem.Allocator) ![:0]u8 {
        _ = self;

        var return_value = try alloc.dupeZ(u8, "something, something");

        return return_value;
    }
};

test "Commit.confirmHash" {
    var headers = try Headers.init(testing.allocator);
    defer headers.deinit();

    _ = try headers.insertHeader("Author", "I Am Spartacus<iamspartacus@example.com>");
    _ = try headers.insertHeader("Committer", "No I Am Spartacus<noiamspartacus@example.com>");

    var parent_edges: []CommitParent = undefined;
    parent_edges.len = 0;
    var tree: HashKey = undefined;
    _ = tree;
}

pub const CommitParent = struct {
    commit: HashKey,
    ptype: ParentType,
};

pub const Tree = struct {
    tree_entries: []TreeEntry,

    pub fn toString(self: Tree, alloc: std.mem.Allocator) ![:0]u8 {
        _ = self;

        var final_value = try alloc.dupeZ(u8, "");
        return final_value;
    }
};

pub const TreeEntry = struct {
    pub const type_name = "tree_entry";

    file_id: FileId,
    blob: HashKey,

    pub fn toString(self: *const TreeEntry, alloc: std.mem.Allocator) ![:0]u8 {
        const sep: [:0]const u8 = " ";

        const fid_hash = try self.file_id.toString(alloc);
        defer alloc.free(fid_hash);

        const blob_hash = try self.blob.toString(alloc);
        defer alloc.free(blob_hash);

        const all_parts = [_][]const u8{ TreeEntry.type_name, fid_hash, blob_hash };
        return try std.mem.joinZ(alloc, sep, &all_parts);
    }
};

// test "TreeEntry.toString" {
//     const expected_string: []const u8 = "tree_entry file_id|path/to/file|sha3_256|2dce61c76e93ee7da2fe615cf5140b54ed0f5346e285b5c90a661f1850c17e41";

//     const path_to_file: []const u8 = "path/to/file";

//     var file_id = try FileId.initAndHash(testing.allocator, path_to_file, null, null, null);
//     defer file_id.deinit();

//     const file_id_string = try file_id.toString(testing.allocator);
//     defer testing.allocator.free(file_id_string);

//     try testing.expectEqualSlices(u8, expected_string, file_id_string);
// }

pub const FileId = struct {
    pub const type_name = "file_id";

    /// The commit pointers are only truly needed for hashing. This points to
    /// the parent commits where this file id came into being. This would be
    /// the merge parents of the commit when this FileId came into existence.
    /// Order of commits must match parent merging order of commit this came
    /// into existence, or hashing will not match properly.
    commits: []HashKey,
    hash_key: HashKey,
    parents: []HashKey,
    path: []const u8,

    /// Asserts that `len` of `path` is greater than 0.
    pub fn init(path: []const u8, hash_key: HashKey, parents_opt: ?[]HashKey, commits_opt: ?[]HashKey) FileId {
        assert(path.len > 0);

        var commits: []HashKey = commits_opt orelse &[_]HashKey{};
        var parents: []HashKey = parents_opt orelse &[_]HashKey{};
        return FileId{
            .commits = commits,
            .hash_key = hash_key,
            .parents = parents,
            .path = path,
        };
    }

    /// The allocator is used to allocate the internal hash string inside the hash key.
    pub fn initAndHash(alloc: std.mem.Allocator, path: []const u8, hash_algo: ?HashAlgo, parents_opt: ?[]HashKey, commits_opt: ?[]HashKey) !FileId {
        const final_algo = hash_algo orelse HashAlgo.default;
        var temp = FileId.init(path, undefined, parents_opt, commits_opt);

        var hash_key = try FileId.hash(&temp, alloc, final_algo);

        return FileId.init(path, hash_key, parents_opt, commits_opt);
    }

    pub fn deinit(self: *FileId) void {
        self.hash_key.deinit();
    }

    pub fn toString(self: *const FileId, alloc: std.mem.Allocator) ![:0]u8 {
        return try self.hash_key.fmtToString(alloc, .{ FileId.type_name, self.path });
    }

    pub fn createHash(alloc: std.mem.Allocator, path: []const u8, hash_algo: ?HashAlgo, parents_opt: ?[]HashKey, commits_opt: ?[]HashKey) !HashKey {
        var temp = try FileId.initAndHash(alloc, path, hash_algo, parents_opt, commits_opt);

        return temp.hash_key;
    }

    pub fn hash(self: *FileId, alloc: std.mem.Allocator, hash_algo: HashAlgo) !HashKey {
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        var arena_alloc = arena.allocator();

        var buf_array = std.ArrayList(u8).init(alloc);
        defer buf_array.deinit();

        for (self.commits) |commit| {
            const commit_string = try commit.toString(arena_alloc);
            try buf_array.appendSlice(commit_string);
            try buf_array.append('\n');
        }

        for (self.parents) |parent| {
            const parent_string = try parent.toString(arena_alloc);
            try buf_array.appendSlice(parent_string);
            try buf_array.append('\n');
        }

        try buf_array.appendSlice(self.path);
        try buf_array.append('\n');

        var buf_stream = std.io.fixedBufferStream(buf_array.items);
        var buf_reader = buf_stream.reader();

        return try HashKey.init(hash_algo, alloc, buf_reader);
    }
};

test "FileId.nakedHash" {
    const expected_hash: []const u8 = "2dce61c76e93ee7da2fe615cf5140b54ed0f5346e285b5c90a661f1850c17e41";

    const path_to_file: []const u8 = "path/to/file";

    var hash_key = try FileId.createHash(testing.allocator, path_to_file, null, null, null);
    defer hash_key.deinit();

    try testing.expectEqualSlices(u8, expected_hash, hash_key.hash);
}

test "FileId.toString" {
    const expected_string: []const u8 = "file_id|path/to/file|sha3_256|2dce61c76e93ee7da2fe615cf5140b54ed0f5346e285b5c90a661f1850c17e41";

    const path_to_file: []const u8 = "path/to/file";

    var file_id = try FileId.initAndHash(testing.allocator, path_to_file, null, null, null);
    defer file_id.deinit();

    const file_id_string = try file_id.toString(testing.allocator);
    defer testing.allocator.free(file_id_string);

    try testing.expectEqualSlices(u8, expected_string, file_id_string);
}

pub const Blob = struct {
    pub const type_name = "blob";

    hash_key: HashKey,
    num_bytes: u64,

    pub fn toString(self: *const Blob, alloc: std.mem.Allocator) ![:0]u8 {
        var numbuf: [32]u8 = undefined;
        const pos = std.fmt.formatIntBuf(&numbuf, self.num_bytes, 10, .lower, .{});
        return try self.hash_key.fmtToString(alloc, .{ Blob.type_name, numbuf[0..pos] });
    }
};

test "Blob.toString" {
    const expected_string: []const u8 = "blob|5|sha3_256|deadbeef";
    const fake_hash = "deadbeef";

    var blob: Blob = .{
        .hash_key = .{
            .hash = fake_hash,
            .hash_algo = .sha3_256,
        },
        .num_bytes = 5,
    };

    const blob_string = try blob.toString(testing.allocator);
    defer testing.allocator.free(blob_string);

    try testing.expectEqualSlices(u8, expected_string, blob_string);
}
