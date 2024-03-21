//! We use slices with a null sentinel throughout the data structures primarily
//! because we need to interoperate with SQLite and other C code a lot, and
//! forcing the sentinel to always be there from the beginning makes interop
//! easier.

const std = @import("std");

const log = std.log.scoped(.ds);

pub const HashKey = struct {
    hash: [:0]const u8,
    hash_algo: [:0]const u8,
};

pub const StringMap = std.AutoHashMap([:0]const u8, [:0]const u8);

pub const Commit = struct {
    alloc: std.mem.Allocator,
    headers: StringMap,
    tree: *Tree,
    parent_edges: []*CommitParent,

    pub fn init(alloc: std.mem.Allocator, tree: *Tree, parent_edges: []*CommitParent) !Commit {
        return .{
            .alloc = alloc,
            .headers = StringMap.init(alloc),
            .tree = tree,
            .parent_edges = parent_edges,
        };
    }

    pub fn deinit(self: *Commit) void {
        var it = self.headers.iterator();
        while (it.next()) |entry| {
            self.alloc.free(entry.key_ptr.*);
            self.alloc.free(entry.value_ptr.*);
        }
        self.headers.deinit();
    }

    pub fn insertHeader(self: *Commit, key: [:0]const u8, value: [:0]const u8) !void {
        if (std.mem.containsAtLeast(u8, key, 1, "=")) {
            log.err("Key contains illegal characters: {s}", key);
            return error.EqualSignInKey;
        }

        const key_copy = self.alloc.dupeZ(u8, key);
        const value_copy = self.alloc.dupeZ(u8, value);

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

pub const ParentType = enum {
    regular,
    merge,
    cherry_pick,
    revert,
};

pub const Tree = struct {
    tree_entries: []*TreeEntry,
};

pub const TreeEntry = struct {
    file_id: *FileId,
    blob: *Blob,
};

pub const FileId = struct {
    hash: [:0]const u8,
    hash_algo: [:0]const u8,
    path: [:0]const u8,
    parents: []*FileId,
};

pub const Blob = struct {
    hash: [:0]const u8,
    hash_algo: [:0]const u8,
    chunks: []*Chunk,
};

pub const Chunk = struct {
    hash: [:0]const u8,
    hash_algo: [:0]const u8,
    data: []const u8,
};
