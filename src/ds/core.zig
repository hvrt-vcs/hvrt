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

const utf8_space: u8 = ' ';
const utf8_new_line: u8 = '\n';

// TODO: convert all object pointers into HashKey objects. These can then be
// used to point into HashMaps holding the actual objects.
pub const CommitHashMap = std.HashMap(HashKey, Commit, HashKey.HashMapContext, 80);
pub const TreeHashMap = std.HashMap(HashKey, Tree, HashKey.HashMapContext, 80);
pub const FileIdHashMap = std.HashMap(HashKey, FileId, HashKey.HashMapContext, 80);
pub const BlobHashMap = std.HashMap(HashKey, Blob, HashKey.HashMapContext, 80);

pub const CompressionAlgo = enum {
    // TODO: store no compression algo as string "none" in database, instead of a SQL `NULL` value.
    none,
    zstd,

    pub fn compress(self: CompressionAlgo, reader: anytype, writer: anytype) !void {
        _ = writer;
        _ = reader;
        _ = self;
    }
};

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
        const reader = buf_stream.reader();

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

    pub fn toString(self: HashKey, alloc: std.mem.Allocator) ![:0]u8 {
        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();

        const writer = array_list.writer();
        try self.writeSelf(writer);

        return try array_list.toOwnedSliceSentinel(0);
    }

    pub fn writeSelf(self: HashKey, writer: anytype) !void {
        const parts = [_][]const u8{ @tagName(self.hash_algo), self.hash };
        for (parts, 0..) |part, i| {
            if (i != 0) try writer.writeAll(hash_key_sep);
            try writer.writeAll(part);
        }
    }

    pub fn fmtToString(self: *const HashKey, alloc: std.mem.Allocator, parts: anytype) ![:0]u8 {
        const all_parts = parts ++ [_][]const u8{ @tagName(self.hash_algo), self.hash };
        return try std.mem.joinZ(alloc, hash_key_sep, &all_parts);
    }

    pub fn prePostToString(self: *const HashKey, alloc: std.mem.Allocator, prefix_parts: anytype, postfix_parts: anytype) ![:0]u8 {
        const hash_str = try self.toString(alloc);
        defer alloc.free(hash_str);

        const all_parts = prefix_parts ++ [_][]const u8{hash_str} ++ postfix_parts;
        return try std.mem.joinZ(alloc, " ", &all_parts);
    }

    pub fn prePostWriter(self: *const HashKey, prefix_parts_opt: ?[]const []const u8, postfix_parts_opt: ?[]const []const u8, writer: anytype) !void {
        const prefix_parts = prefix_parts_opt orelse &.{};
        const postfix_parts = postfix_parts_opt orelse &.{};

        for (prefix_parts, 0..) |part, i| {
            if (i != 0) try writer.writeByte(' ');
            try writer.writeAll(part);
        }

        if (prefix_parts.len != 0) try writer.writeByte(' ');
        try self.writeSelf(writer);

        for (postfix_parts) |part| {
            try writer.writeByte(' ');
            try writer.writeAll(part);
        }
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
    const reader = buf_stream.reader();

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
    const reader = buf_stream.reader();

    // declare as var to force runtime evaluation
    var hash_algo: HashAlgo = undefined;
    hash_algo = .sha1;

    const actual = try HashKey.init(hash_algo, testing.allocator, reader);
    defer actual.deinit();

    try testing.expectEqual(HashAlgo.sha1, actual.hash_algo);
    try testing.expect(std.mem.eql(u8, expected_hash, actual.hash));
}

const Commit = struct {
    tree: HashKey,

    parents: []CommitParent,

    /// Author name/email combo
    author: [:0]const u8,

    /// Seconds since the epoch
    author_time: i64,

    /// UTC offset in minutes. Between -720 and 720.
    author_utc_offset: i11,

    /// Committer name/email combo
    committer: [:0]const u8,

    /// Seconds since the epoch
    committer_time: i64,

    /// UTC offset in minutes. Between -720 and 720.
    committer_utc_offset: i11,

    /// Commit message
    message: [:0]const u8,

    fn writeAuthor(author: [:0]const u8, author_time: i64, author_utc_offset: i11, writer: anytype) !void {
        const space: u8 = ' ';
        const fill: u8 = '0';

        try writer.writeAll(author);
        try writer.writeByte(space);

        try std.fmt.formatInt(author_time, 10, .lower, .{}, writer);
        try writer.writeByte(space);

        const sign: u8 = if (author_utc_offset < 0) '-' else '+';
        try writer.writeByte(sign);

        const hours = @divTrunc(author_utc_offset, 60);
        const minutes = @mod(author_utc_offset, 60);

        var buf: [4]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        const fb_writer = fbs.writer();

        try std.fmt.formatInt(hours, 10, .lower, .{}, fb_writer);
        if (fbs.getWritten().len == 1) {
            try writer.writeByte(fill);
        }
        try writer.writeAll(fbs.getWritten());

        fbs.reset();
        try std.fmt.formatInt(minutes, 10, .lower, .{}, fb_writer);
        if (fbs.getWritten().len == 1) {
            try writer.writeByte(fill);
        }
        try writer.writeAll(fbs.getWritten());
    }

    pub fn writeHashBytes(self: Commit, writer: anytype) !void {
        const new_line: u8 = '\n';

        try self.tree.prePostWriter(&.{"tree"}, null, writer);
        try writer.writeByte(new_line);

        for (self.parents) |parent| {
            try parent.writeSelf(writer);
            try writer.writeByte(new_line);
        }

        try writer.writeAll("author ");
        try writeAuthor(self.author, self.author_time, self.author_utc_offset, writer);
        try writer.writeByte(new_line);

        try writer.writeAll("committer ");
        try writeAuthor(self.committer, self.committer_time, self.committer_utc_offset, writer);
        try writer.writeByte(new_line);

        try writer.writeByte(new_line);
        try writer.writeAll(self.message);
        try writer.writeByte(new_line);
    }
};

test "commit objects" {
    const alloc = std.testing.allocator;

    const expected: []const u8 =
        \\tree sha3_256|deadbeef
        \\author Some author guy <author@example.com> 1 +1100
        \\committer Some committer guy <committer@example.com> 2 +1052
        \\
        \\Here is some sort of message
        \\
    ;

    var parents: []CommitParent = undefined;
    parents.len = 0;

    const commit_obj = Commit{
        .author = "Some author guy <author@example.com>",
        .author_time = 1,
        .author_utc_offset = 660,
        .committer = "Some committer guy <committer@example.com>",
        .committer_time = 2,
        .committer_utc_offset = 652,
        .message = "Here is some sort of message",
        .parents = parents,
        .tree = .{ .hash = "deadbeef" },
    };

    // std.debug.print("commit_obj: {}\n", .{commit_obj});

    var array = std.ArrayList(u8).init(alloc);
    defer array.deinit();

    const writer = array.writer();
    try commit_obj.writeHashBytes(writer);
    const hash_bytes = array.items;

    try std.testing.expectEqualStrings(expected, hash_bytes);
}

pub const CommitParent = struct {
    commit: HashKey,
    parent_type: ParentType,

    pub fn toString(self: CommitParent, alloc: std.mem.Allocator) ![:0]u8 {
        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();

        const writer = array_list.writer();
        try self.writeSelf(writer);

        return try array_list.toOwnedSliceSentinel(0);
    }

    pub fn writeSelf(self: CommitParent, writer: anytype) !void {
        try self.commit.prePostWriter(
            &.{ "parent", @tagName(self.parent_type) },
            null,
            writer,
        );
    }

    test toString {
        const expected = "parent regular sha3_256|deadbeef";

        const commit_parent = CommitParent{ .commit = .{ .hash = "deadbeef" }, .parent_type = .regular };
        const actual = try commit_parent.toString(std.testing.allocator);
        defer std.testing.allocator.free(actual);

        try std.testing.expectEqualStrings(expected, actual);
    }
};

pub const Tree = struct {
    tree_entries: []TreeEntry,

    pub fn writeSelf(self: Tree, writer: anytype) !void {
        // Assume entries are already sorted
        for (self.tree_entries) |entry| {
            try entry.writeSelf(writer);
            try writer.writeByte(utf8_new_line);
        }
    }
};

test "Tree.writeSelf" {
    const expected =
        \\040000 tree sha3_256|deadbeef1 filename1
        \\100644 blob sha3_256|deadbeef2 filename2
        \\100644 blob sha3_256|deadbeef3 filename3
        \\
    ;
    const alloc = std.testing.allocator;

    var array = std.ArrayList(u8).init(alloc);
    defer array.deinit();

    const writer = array.writer();

    const hash1: HashKey = .{ .hash = "deadbeef1" };
    const hash2: HashKey = .{ .hash = "deadbeef2" };
    const hash3: HashKey = .{ .hash = "deadbeef3" };
    var entry1: TreeEntry = .{ .hash = hash1, .mode = undefined, .name = "filename1" };
    var entry2: TreeEntry = .{ .hash = hash2, .mode = undefined, .name = "filename2" };
    var entry3: TreeEntry = .{ .hash = hash3, .mode = undefined, .name = "filename3" };

    @memcpy(&entry1.mode, "040000");
    @memcpy(&entry2.mode, "100644");
    @memcpy(&entry3.mode, "100644");

    var tree_entries = [_]TreeEntry{
        entry1,
        entry2,
        entry3,
    };
    const test_tree: Tree = Tree{ .tree_entries = &tree_entries };

    try test_tree.writeSelf(writer);

    try std.testing.expectEqualStrings(expected, array.items);
}

/// https://stackoverflow.com/a/8347325/1733321
pub const EntryMode = enum([:0]const u8) {
    directory = "040000",
    regular_file = "100644",
    group_writable_file = "100664",
    executable_file = "100755",
    symbolic_link = "120000",
    gitlink = "160000",
};

pub const TreeEntry = struct {
    // All trees (i.e. directories) start with "04" as their mode.
    const tree_mode_prefix: [:0]const u8 = "04";

    mode: [6:0]u8,
    hash: HashKey,
    name: [:0]const u8,

    pub fn writeSelf(self: TreeEntry, writer: anytype) !void {
        try writer.writeAll(&self.mode);
        try writer.writeByte(utf8_space);
        if (std.mem.startsWith(u8, &self.mode, tree_mode_prefix)) {
            try writer.writeAll("tree");
        } else {
            try writer.writeAll("blob");
        }
        try writer.writeByte(utf8_space);
        try self.hash.writeSelf(writer);
        try writer.writeByte(utf8_space);
        try writer.writeAll(self.name);
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

        const commits: []HashKey = commits_opt orelse &[_]HashKey{};
        const parents: []HashKey = parents_opt orelse &[_]HashKey{};
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

        const hash_key = try FileId.hash(&temp, alloc, final_algo);

        return FileId.init(path, hash_key, parents_opt, commits_opt);
    }

    pub fn deinit(self: *FileId) void {
        self.hash_key.deinit();
    }

    pub fn toString(self: *const FileId, alloc: std.mem.Allocator) ![:0]u8 {
        return try self.hash_key.fmtToString(alloc, .{ FileId.type_name, self.path });
    }

    pub fn createHash(alloc: std.mem.Allocator, path: []const u8, hash_algo: ?HashAlgo, parents_opt: ?[]HashKey, commits_opt: ?[]HashKey) !HashKey {
        const temp = try FileId.initAndHash(alloc, path, hash_algo, parents_opt, commits_opt);

        return temp.hash_key;
    }

    pub fn hash(self: *FileId, alloc: std.mem.Allocator, hash_algo: HashAlgo) !HashKey {
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        const arena_alloc = arena.allocator();

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
        const buf_reader = buf_stream.reader();

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
