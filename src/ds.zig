//! We use slices with a null sentinel throughout the data structures primarily
//! because we need to interoperate with SQLite and other C code a lot, and
//! forcing the sentinel to always be there from the beginning makes interop
//! easier.

const std = @import("std");
const testing = std.testing;

const hash_mod = std.crypto.hash;

const log = std.log.scoped(.ds);

pub const HashAlgo = enum {
    sha3_256,
    sha1, // for interop with git, maybe?
};

pub fn hashAlgoEnumToType(comptime hash_algo: HashAlgo) type {
    return switch (hash_algo) {
        .sha3_256 => hash_mod.sha3.Sha3_256,
        .sha1 => hash_mod.Sha1,
    };
}

test "test hashAlgoEnumToType" {
    const sha3_type = hashAlgoEnumToType(.sha3_256);
    try testing.expectEqual(hash_mod.sha3.Sha3_256, sha3_type);
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

    pub fn toStringZ(self: HashKey, alloc: std.mem.Allocator) ![:0]u8 {
        const parts = [_][]const u8{ @tagName(self.hash_algo), self.hash };
        return try std.mem.joinZ(alloc, hash_key_sep, &parts);
    }
};

test "HashKey toStringZ" {
    const hk = HashKey{ .hash = "deadbeef", .hash_algo = .sha3_256 };

    const hks = try hk.toStringZ(testing.allocator);
    defer testing.allocator.free(hks);

    const expected = "sha3_256|deadbeef";
    try testing.expect(std.mem.eql(u8, expected, hks));
}

pub const StringMap = std.AutoHashMap([:0]const u8, [:0]const u8);

pub const Commit = struct {
    const illegal_header_chars: [:0]const u8 = "=\n";

    alloc: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    hash_key: HashKey,
    headers: StringMap,
    parent_edges: []*CommitParent,
    tree: *Tree,

    pub fn init(alloc: std.mem.Allocator, hash_key: HashKey, parent_edges: []*CommitParent, tree: *Tree) !Commit {
        var arena = std.heap.ArenaAllocator.init(alloc);
        var arena_alloc = arena.allocator();

        return .{
            .alloc = arena_alloc,
            .arena = arena,
            .hash_key = hash_key,
            .headers = StringMap.init(arena_alloc),
            .parent_edges = parent_edges,
            .tree = tree,
        };
    }

    pub fn deinit(self: *Commit) void {
        self.headers.deinit();
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn insertHeader(self: *Commit, key: [:0]const u8, value: [:0]const u8) !void {
        if (std.mem.indexOfAny(u8, key, illegal_header_chars)) |idx| {
            log.err("Key \'{s}\' contains illegal character: {s}", key, key[idx]);
            return error.IllegalHeaderChar;
        } else if (std.mem.indexOfAny(u8, value, illegal_header_chars)) |idx| {
            log.err("value \'{s}\' contains illegal character: {s}", value, value[idx]);
            return error.IllegalHeaderChar;
        }

        const key_copy = try self.alloc.dupeZ(u8, key);
        const value_copy = try self.alloc.dupeZ(u8, value);

        try self.headers.getOrPutValue(key_copy, value_copy);
    }

    pub fn toStringZ(self: *Commit, alloc: std.mem.Allocator) ![:0]u8 {
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
    chunks: []*Chunk,
};

pub const Chunk = struct {
    hash_key: HashKey,
    data: []const u8,
};
