const core = @import("core.zig");
const HashKey = core.HashKey;
const Blob = core.Blob;

/// When blobs are stored in DB, they are split into chunks in order to stay
/// within the blob/bytea limits of the backing database. The data structures
/// below represent these chunks.
pub const BlobChunks = struct {
    blob: *Blob,

    /// Within a single blob, chunkref byte ranges must not overlap.
    chunks: []ChunkRef,
};

pub const ChunkRef = struct {
    start_byte: u64,
    end_byte: u64,
    chunk: *Chunk,
};

pub const Chunk = struct {
    hash_key: HashKey,
    data: []const u8,
};
