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
const Writer = std.Io.Writer;

const assert = std.debug.assert;

const testing = std.testing;

const utf8_new_line: u8 = '\n';
const utf8_solidus: u8 = '/';
const utf8_space: u8 = ' ';

/// Like git, a hash in Havarti can theoretically point to anything. Use a
/// tagged union type to represent this.
pub const Object = union(enum) {
    blob: Blob,
    commit: Commit,
    tree: Tree,
};

// TODO: convert all object pointers into HashKey objects. These can then be
// used to point into HashMaps holding the actual objects.
pub const ObjectHashMap = std.HashMap(HashKey, Object, HashKey.HashMapContext, 80);

pub const CompressionAlgo = enum {
    // TODO: store no compression algo as string "none" in database, instead of a SQL `NULL` value.
    none,
    zstd,
};

var fifo = std.fifo.LinearFifo(u8, .{ .Static = 1024 * 4 }).init();

pub const HashAlgo = enum {
    sha1, // for interop with git, maybe?
    sha3_256,

    pub const default = .sha3_256;

    // TODO: calculate `max_digest_length` using `@typeInfo().fields.type` so
    // that it dynamically deals with adding/removing union fields/types.
    const max_digest_length = std.mem.max(
        comptime_int,
        &.{
            std.crypto.hash.Sha1.digest_length,
            std.crypto.hash.sha3.Sha3_256.digest_length,
        },
    );

    /// An Array type big enough to hold the largest largest possible hexified
    /// digest, plus a trailing 0 sentinel. Non-hexified digests, or digests
    /// from hash algorithms with smaller bit widths will fit within this.
    ///
    /// The functions that use this take it as a pointer and return a slice of
    /// it after filling it with the requested digest type.
    pub const Buffer = [max_digest_length * 2:0]u8;

    pub fn HasherType(comptime hash_algo: HashAlgo) type {
        return switch (hash_algo) {
            .sha1 => std.crypto.hash.Sha1,
            .sha3_256 => std.crypto.hash.sha3.Sha3_256,
        };
    }

    fn toWriterComptime(comptime hash_algo: HashAlgo, reader: anytype, writer: anytype) !void {
        const hasher_type = hash_algo.HasherType();
        var hasher = hasher_type.init(.{});

        try fifo.pump(reader, hasher.writer());

        var digest_buf: [hasher_type.digest_length]u8 = undefined;
        hasher.final(&digest_buf);
        const file_digest_hex = std.fmt.bytesToHex(digest_buf, .lower);
        try writer.writeAll(&file_digest_hex);
    }

    pub fn toWriter(hash_algo: HashAlgo, reader: anytype, writer: anytype) !void {
        return switch (hash_algo) {
            .sha1 => try HashAlgo.toWriterComptime(.sha1, reader, writer),
            .sha3_256 => try HashAlgo.toWriterComptime(.sha3_256, reader, writer),
        };
    }

    /// Allocator is used to allocate the hash string. Caller is responsible
    /// for releasing the memory on the returned string.
    pub fn fromReader(hash_algo: HashAlgo, alloc: std.mem.Allocator, reader: anytype) ![:0]u8 {
        var array = std.ArrayList(u8).init(alloc);
        defer array.deinit();

        try hash_algo.toWriter(reader, array.writer());

        return try array.toOwnedSliceSentinel(0);
    }
};

test "HashAlgo.toType" {
    const sha1_type = HashAlgo.HasherType(.sha1);
    try testing.expectEqual(std.crypto.hash.Sha1, sha1_type);

    const sha3_type = HashAlgo.HasherType(.sha3_256);
    try testing.expectEqual(std.crypto.hash.sha3.Sha3_256, sha3_type);
}

pub const Sha3_256 = struct {
    const Self = @This();
    const HashType = std.crypto.hash.sha3.Sha3_256;
    const digest_length = HashType.digest_length;
    hash_algo: HashAlgo = .sha3_256,
    hasher: std.Io.Writer.Hashing(HashType),

    pub fn init() Self {
        return .{
            .hasher = .init(&.{}),
        };
    }

    pub fn digest(s: Self) [digest_length]u8 {
        var out_buf: [digest_length]u8 = undefined;
        var hasher_copy = s.hasher.hasher;
        hasher_copy.final(&out_buf);
        return out_buf;
    }

    pub fn hexDigest(s: Self) [digest_length * 2:0]u8 {
        var digest_buf: [digest_length]u8 = undefined;
        var hasher_copy = s.hasher.hasher;
        hasher_copy.final(&digest_buf);

        const hex_buf = std.fmt.bytesToHex(digest_buf, .lower);
        var hex_bufz: [digest_length * 2:0]u8 = undefined;
        @memcpy(hex_bufz[0..hex_buf.len], &hex_buf);
        hex_bufz[hex_buf.len] = 0;
        return hex_bufz;
    }
};

pub const Hasher = union(HashAlgo) {
    sha1: HashAlgo.HasherType(.sha1), // for interop with git, maybe?
    sha3_256: HashAlgo.HasherType(.sha3_256),

    // TODO: calculate `max_digest_length` using `@typeInfo().fields.type` so
    // that it dynamically deals with adding/removing union fields/types.
    const max_digest_length = std.mem.max(
        comptime_int,
        &.{ std.crypto.hash.Sha1.digest_length, std.crypto.hash.sha3.Sha3_256.digest_length },
    );

    /// An Array type big enough to hold the largest largest possible hexified
    /// digest, plus a trailing 0 sentinel. Non-hexified digests, or digests
    /// from hash algorithms with smaller bit widths will fit within this.
    ///
    /// The functions that use this take it as a pointer and return a slice of
    /// it after filling it with the requested digest type.
    pub const Buffer = [max_digest_length * 2:0]u8;

    pub fn init(hash_algo: ?HashAlgo) Hasher {
        return switch (hash_algo orelse HashAlgo.default) {
            .sha1 => .{ .sha1 = HashAlgo.HasherType(.sha1).init(.{}) },
            .sha3_256 => .{ .sha3_256 = HashAlgo.HasherType(.sha3_256).init(.{}) },
        };
    }

    // Hasher writers cannot throw errors
    pub const Error = error{};
    // pub const Writer = std.Io.Writer(*Hasher, Error, write);

    pub fn write(self: *Hasher, bytes: []const u8) Error!usize {
        switch (self.*) {
            .sha1 => self.sha1.update(bytes),
            .sha3_256 => self.sha3_256.update(bytes),
        }
        return bytes.len;
    }

    pub fn getDigestLength(self: Hasher) usize {
        return switch (self) {
            .sha1 => HashAlgo.HasherType(.sha1).digest_length,
            .sha3_256 => HashAlgo.HasherType(.sha3_256).digest_length,
        };
    }

    /// Return a slice of the `out` array argument containing the hash digest
    /// as raw binary bytes.
    pub fn final(self: *Hasher, out: *Buffer) []u8 {
        return switch (self.*) {
            .sha1 => Hasher.genericFinal(&self.sha1, out),
            .sha3_256 => Hasher.genericFinal(&self.sha3_256, out),
        };
    }

    /// Return a slice of the `out` array argument containing the hash digest
    /// as a hex string. This is twice as long as the digest produced by
    /// `final`, but it has the benefit that it can be treated like a plain old
    /// ASCII string.
    pub fn hexFinal(self: *Hasher, out: *Buffer) [:0]u8 {
        return switch (self.*) {
            .sha1 => Hasher.genericHexFinal(&self.sha1, out),
            .sha3_256 => Hasher.genericHexFinal(&self.sha3_256, out),
        };
    }

    fn genericFinal(hasher: anytype, out: *Buffer) []u8 {
        const digest_length = @TypeOf(hasher.*).digest_length;
        var digest_buf: [digest_length]u8 = undefined;
        hasher.final(&digest_buf);
        @memcpy(out[0..digest_buf.len], &digest_buf);
        return out[0..digest_buf.len];
    }

    fn genericHexFinal(hasher: anytype, out: *Buffer) [:0]u8 {
        const digest_length = @TypeOf(hasher.*).digest_length;
        var digest_buf: [digest_length]u8 = undefined;
        hasher.final(&digest_buf);

        const hex_buf = std.fmt.bytesToHex(digest_buf, .lower);
        @memcpy(out[0..hex_buf.len], &hex_buf);
        out[hex_buf.len] = 0;
        return out[0..hex_buf.len :0];
    }
};

pub const ParentType = enum {
    regular,
    merge,
    cherry_pick,
    revert,
};

pub const HashKey = struct {
    const Self = @This();

    pub const hash_key_sep: [:0]const u8 = "|";

    /// The allocator that originally allocated the hash string. If not
    /// present, will not be used during deinit.
    alloc_opt: ?std.mem.Allocator = null,
    hash: [:0]const u8,
    hash_algo: HashAlgo = HashAlgo.default,

    pub const HashMapContext = struct {
        pub fn hash(_: @This(), a: HashKey) u64 {
            var final_hash: u64 = 0;
            for (@tagName(a.hash_algo)) |byte| final_hash = final_hash +% byte;
            for (a.hash) |byte| final_hash = final_hash +% byte;
            return final_hash;
        }

        pub fn eql(_: @This(), a: HashKey, b: HashKey) bool {
            return a.hash_algo == b.hash_algo and std.mem.eql(u8, a, b);
        }
    };

    pub fn deinit(self: HashKey) void {
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
    /// manage the life time of hash string memory elsewhere.
    pub fn init(hash_algo: HashAlgo, alloc: std.mem.Allocator, reader: anytype) !HashKey {
        const file_digest_hexz = try hash_algo.fromReader(alloc, reader);

        return .{
            .alloc_opt = alloc,
            .hash = file_digest_hexz,
            .hash_algo = hash_algo,
        };
    }

    pub fn equal(self: HashKey, other: HashKey) bool {
        return self.hash_algo == other.hash_algo and std.mem.eql(u8, self.hash, other.hash);
    }

    pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const parts = [_][]const u8{ @tagName(self.hash_algo), self.hash };
        for (parts, 0..) |part, i| {
            if (i != 0) try writer.writeAll(hash_key_sep);
            try writer.writeAll(part);
        }
    }

    pub fn prePostWriter(self: Self, prefix_parts_opt: ?[]const []const u8, postfix_parts_opt: ?[]const []const u8, writer: *std.Io.Writer) !void {
        const prefix_parts = prefix_parts_opt orelse &.{};
        const postfix_parts = postfix_parts_opt orelse &.{};

        for (prefix_parts, 0..) |part, i| {
            if (i != 0) try writer.writeByte(utf8_space);
            try writer.writeAll(part);
        }

        if (prefix_parts.len != 0) try writer.writeByte(utf8_space);
        try writer.print("{f}", .{self});

        for (postfix_parts) |part| {
            try writer.writeByte(utf8_space);
            try writer.writeAll(part);
        }
    }
};

const Commit = struct {
    const Self = @This();

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

    fn writeAuthor(author: [:0]const u8, author_time: i64, author_utc_offset: i11, writer: *std.Io.Writer) !void {
        const sign: u8 = if (author_utc_offset < 0) '-' else '+';
        const hours = @abs(@divTrunc(author_utc_offset, 60));
        const minutes = @abs(@mod(author_utc_offset, 60));

        try writer.print("{s} {d} {c}", .{ author, author_time, sign });

        if (hours < 10) try writer.writeByte('0');
        try writer.print("{d}", .{hours});

        if (minutes < 10) try writer.writeByte('0');
        try writer.print("{d}", .{minutes});
    }

    pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const new_line: u8 = '\n';

        try self.tree.prePostWriter(&.{"tree"}, null, writer);
        try writer.writeByte(new_line);

        for (self.parents) |parent| {
            try writer.print("{f}\n", .{parent});
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

    // var alloc_writer = std.Io.Writer.Allocating.init(alloc);
    var alloc_writer = try std.Io.Writer.Allocating.initCapacity(alloc, 1024 * 64);
    defer alloc_writer.deinit();

    var writer = &alloc_writer.writer;
    try writer.print("{f}", .{commit_obj});

    const hash_bytes = alloc_writer.written();

    try std.testing.expectEqualStrings(expected, hash_bytes);
}

pub const CommitParent = struct {
    const Self = @This();
    commit: HashKey,
    parent_type: ParentType,

    /// Caller owns the returned slice.
    pub fn toString(self: Self, gpa: std.mem.Allocator) ![:0]u8 {
        var alloc_writer = std.Io.Writer.Allocating.init(gpa);
        defer alloc_writer.deinit();

        try alloc_writer.writer.print("{f}", .{self});

        return try alloc_writer.toOwnedSliceSentinel(0);
    }

    pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
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
    const Self = @This();

    // Entries are `const` because we assume entries are already sorted and do
    // not need to be modified after Tree object is created.
    tree_entries: []const TreeEntry,

    /// Sorts `tree_entries` in place before wrapping and returning in `Tree`
    /// struct.
    ///
    /// If sorting is not desired, just use `struct` literal syntax to create
    /// `Tree` object.
    pub fn init(tree_entries: []TreeEntry) Tree {
        std.sort.heap(TreeEntry, tree_entries, void{}, TreeEntry.lessThan);
        return .{ .tree_entries = tree_entries };
    }

    pub fn writeSelf(self: Tree, writer: anytype) !void {
        for (self.tree_entries) |entry| {
            try entry.writeSelf(writer);
            try writer.writeByte(utf8_new_line);
        }
    }

    pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        for (self.tree_entries) |entry| {
            try writer.print("{f}\n", .{entry});
        }
    }
};

test "Tree.writeSelf" {
    const alloc = std.testing.allocator;

    const expected =
        \\040000 tree sha3_256|deadbeef1 filename1
        \\100644 blob sha3_256|deadbeef2 filename2
        \\100644 blob sha3_256|deadbeef3 filename3
        \\
    ;

    var tree_entries = [_]TreeEntry{
        .{ .hash = .{ .hash = "deadbeef2" }, .mode = .regular_file, .name = "filename2" },
        .{ .hash = .{ .hash = "deadbeef1" }, .mode = .directory, .name = "filename1" },
        .{ .hash = .{ .hash = "deadbeef3" }, .mode = .regular_file, .name = "filename3" },
    };
    const test_tree: Tree = Tree.init(&tree_entries);

    var alloc_writer = std.Io.Writer.Allocating.init(alloc);
    defer alloc_writer.deinit();

    try alloc_writer.writer.print("{f}", .{test_tree});
    const actual = try alloc_writer.toOwnedSlice();
    defer alloc.free(actual);

    try std.testing.expectEqualStrings(expected, actual);
}

/// For the sake of imitating prior art, and perhaps easing compatibility,
/// we're just using the same filemode bits that git does for now. See link
/// here: https://stackoverflow.com/a/8347325/1733321
pub const TreeEntryMode = enum(u32) {
    const Self = @This();

    directory = 0o040000,
    regular_file = 0o100644,
    group_writable_file = 0o100664,
    executable_file = 0o100755,
    symbolic_link = 0o120000,

    pub fn toString(self: TreeEntryMode) [:0]const u8 {
        // Instead of dynamically formatting the int values, we just hardcode
        // the strings since there are only a few anyway. Also, this way
        // doesn't require allocating any strings at runtime.
        return switch (self) {
            .directory => "040000",
            .regular_file => "100644",
            .group_writable_file => "100664",
            .executable_file => "100755",
            .symbolic_link => "120000",
        };
    }

    pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll(self.toString());
    }

    pub fn treeOrBlob(self: TreeEntryMode) [:0]const u8 {
        return switch (self) {
            .directory => "tree",
            else => "blob",
        };
    }
};

pub const TreeEntry = struct {
    const Self = @This();

    mode: TreeEntryMode,
    hash: HashKey,
    name: [:0]const u8,

    pub fn deinit(self: TreeEntry) void {
        self.hash.deinit();
    }

    pub fn lessThan(_: void, lhs: TreeEntry, rhs: TreeEntry) bool {
        // XXX: Is it worth going through all this trouble to sort like git?

        // Few file systems support names bigger than this:
        // https://en.wikipedia.org/wiki/Comparison_of_file_systems#Limits
        var lhs_buf: [256]u8 = undefined;
        var rhs_buf: [256]u8 = undefined;

        var lhs_key: []const u8 = lhs.name;
        var rhs_key: []const u8 = rhs.name;

        if (lhs.mode == .directory) {
            std.mem.copyForwards(u8, &lhs_buf, lhs.name);
            lhs_buf[lhs.name.len] = utf8_solidus;
            lhs_key = lhs_buf[0..(lhs.name.len + 1)];
        }

        if (rhs.mode == .directory) {
            std.mem.copyForwards(u8, &rhs_buf, rhs.name);
            rhs_buf[rhs.name.len] = utf8_solidus;
            rhs_key = rhs_buf[0..(rhs.name.len + 1)];
        }

        return std.mem.lessThan(u8, lhs_key, rhs_key);
    }

    pub fn writeSelf(self: TreeEntry, writer: anytype) !void {
        try writer.writeAll(self.mode.toString());
        try writer.writeByte(utf8_space);

        try writer.writeAll(self.mode.treeOrBlob());
        try writer.writeByte(utf8_space);

        try self.hash.writeSelf(writer);
        try writer.writeByte(utf8_space);

        try writer.writeAll(self.name);
    }

    pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{s} {s} {f} {s}", .{
            self.mode.toString(),
            self.mode.treeOrBlob(),
            self.hash,
            self.name,
        });
    }
};

pub const Blob = struct {
    hash_key: HashKey,
    num_bytes: u64,
};
