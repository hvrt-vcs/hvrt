const std = @import("std");

const sqlite = @import("sqlite.zig");
const cmd = @import("cmd.zig");

// Good references for git internals:
// * https://wyag.thb.lt/
// * https://git-scm.com/book/en/v2/Git-Internals-Git-Objects

/// All that `main` does is retrieve args and a main allocator for the system,
/// and pass those to `internalMain`. Afterwards, it catches any errors, deals
/// with the error types it explicitly knows how to deal with, and if a
/// different error slips though it just prints a stack trace and exits with a
/// generic exit code of 1.
pub fn main() !void {

    // assume successful exit until we know otherwise
    var status_code: u8 = 0;

    {
        var env_var_buf: [128]u8 = undefined;
        var fba_state = std.heap.FixedBufferAllocator.init(&env_var_buf);
        const fba = fba_state.allocator();

        const debug_opt: ?[]u8 = std.process.getEnvVarOwned(fba, "HVRT_DEBUG") catch null;
        defer if (debug_opt) |debug_slice| fba.free(debug_slice);

        // Get allocator
        var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa_state.deinit();
        const gpa = gpa_state.allocator();

        // c_allocator is vastly faster, but less safe than the current GeneralPurposeAllocator.
        const allocator = if (debug_opt != null) gpa else std.heap.c_allocator;

        // Args parsing from here: https://ziggit.dev/t/read-command-line-arguments/220/7

        // Parse args into string array
        const args = try std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, args);

        cmd.internalMain(allocator, args) catch |err| {
            status_code = switch (err) {
                error.ArgumentError => 2,
                sqlite.Error.SQLITE_ERROR => 3,
                sqlite.Error.SQLITE_CANTOPEN => 4,
                else => {
                    // Any error other than the explicitly listed ones in the
                    // switch should just bubble up normally, printing an error
                    // trace.
                    return err;
                },
            };
        };
    }

    // All resources are cleaned up after the block above, so now we can safely
    // call the `exit` function, which does not return.

    // The only place `exit` should ever be called directly is here in the `main` function
    std.process.exit(status_code);
}

const sql = @import("sql.zig");
const test_alloc = std.testing.allocator;

/// Wrapper to return two hex bytes for every byte read from the internal
/// reader reference. Keeps track of leftover byte, if necessary. Adds a
/// newline character at the specified length.
pub fn HexReader(comptime ReaderType: type, comptime line_max: u64) type {
    return struct {
        internal_reader: ReaderType,
        line_remaining: u64,
        leftover_byte: ?u8,

        pub const max_line_len = line_max;
        pub const Error = ReaderType.Error;
        pub const Reader = std.io.Reader(*Self, Error, read);

        const Self = @This();

        pub fn read(self: *Self, dest: []u8) Error!usize {
            var bytes_written: usize = 0;
            for (dest) |*byte| {
                if (self.leftover_byte) |lob| {
                    byte.* = lob;
                    self.leftover_byte = null;
                } else if (self.line_remaining == 0) {
                    byte.* = '\n';
                    self.line_remaining = max_line_len;
                } else {
                    var result: [1]u8 = undefined;
                    const amt_read = try self.read(result[0..]);
                    if (amt_read == 0) break;
                    const hex = std.fmt.bytesToHex(result, .lower);
                    self.leftover_byte = hex[1];
                    byte.* = hex[0];
                }
                self.line_remaining -= 1;
                bytes_written += 1;
            }
            return bytes_written;
        }

        pub fn reader(self: *Self) Reader {
            return .{ .context = self };
        }
    };
}

/// Convenience function to create a concrete HexReader type and return an
/// instantiation of it.
pub fn hexReader(reader: anytype, comptime line_max: u64) HexReader(@TypeOf(reader), line_max) {
    return .{ .internal_reader = reader, .line_remaining = line_max, .leftover_byte = null };
}

fn test_pathz(alloc: std.mem.Allocator, tmp: *std.testing.TmpDir) ![:0]u8 {
    const tmp_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(tmp_path);

    return try alloc.dupeZ(u8, tmp_path);
}

fn prngRead(prng: std.Random, buffer: []u8) !usize {
    prng.bytes(buffer);
    return buffer.len;
}

fn prngReadHex(prng: std.rand.Random, buffer: []u8) !usize {
    if (buffer.len == 0) return 0;

    const hex_len = buffer.len / 2 + (buffer.len % 2);
    // var base_buff: [hex_len]u8 = undefined;
    const base_buff = try test_alloc.alloc(u8, hex_len);
    defer test_alloc.free(base_buff);
    prng.bytes(base_buff);
    var hex_buf = std.fmt.bytesToHex(base_buff, .lower);
    @memcpy(buffer, hex_buf[0..buffer.len]);
    return buffer.len;
}

fn setup_test_files(dir: *std.fs.Dir, files: []const [:0]const u8) !void {
    const target_sz = 1024 * 8;
    const fifo_buffer_size = 1024 * 4;

    var prng = std.Random.DefaultPrng.init(0);
    const prngRand = prng.random();
    const prng_reader = std.io.Reader(std.Random, anyerror, prngRead){ .context = prngRand };
    const prng_hex_reader = hexReader(prng_reader, 80);
    _ = prng_hex_reader;
    const fifo_buf = try test_alloc.alloc(u8, fifo_buffer_size);
    defer test_alloc.free(fifo_buf);

    var fifo = std.fifo.LinearFifo(u8, .Slice).init(fifo_buf);

    for (files) |file| {
        // std.debug.print("\nWhat is filename? {s}\n", .{file});

        var fp = try dir.createFile(file, .{ .exclusive = true });
        defer fp.close();
        var fp_wrtr = fp.writer();

        try fp_wrtr.print("The filename of this file is '{s}'.\n", .{file});
        try fp_wrtr.print("Enjoy some random hex bytes below:\n", .{});

        var lr = std.io.limitedReader(prng_reader, target_sz);
        // var lr = std.io.limitedReader(prng_hex_reader, target_sz);

        try fifo.pump(lr.reader(), fp.writer());
    }
}

fn setup_init_test(tmp: *std.testing.TmpDir) !void {
    const tmp_pathz = try test_pathz(test_alloc, tmp);
    defer test_alloc.free(tmp_pathz);

    const basic_args = [_][:0]const u8{ "hvrt", "init", tmp_pathz };
    try cmd.internalMain(test_alloc, &basic_args);
}

fn setup_add_test(tmp: *std.testing.TmpDir) !void {
    const tmp_pathz = try test_pathz(test_alloc, tmp);
    defer test_alloc.free(tmp_pathz);

    const files = [_][:0]const u8{ "foo.txt", "bar.txt" };
    try setup_test_files(&tmp.dir, &files);

    var sub_dir = try tmp.dir.makeOpenPath(
        "child_subdir",
        .{ .access_sub_paths = true, .iterate = true, .no_follow = true },
    );
    defer sub_dir.close();
    const files2 = [_][:0]const u8{ "baz.txt", "buz.txt" };
    try setup_test_files(&sub_dir, &files2);

    const basic_args = [_][:0]const u8{ "hvrt", "add", tmp_pathz, files[0], files[1] };
    try cmd.internalMain(test_alloc, &basic_args);
}

fn setup_commit_test(tmp: *std.testing.TmpDir) !void {
    const tmp_pathz = try test_pathz(test_alloc, tmp);
    defer test_alloc.free(tmp_pathz);

    // const files = [_][:0]const u8{ "foo.txt", "bar.txt" };

    // try setup_test_files(tmp, &files);

    const basic_args = [_][:0]const u8{ "hvrt", "commit", tmp_pathz, "Some message" };
    try cmd.internalMain(test_alloc, &basic_args);
}

test "invoke with init sub-command" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try setup_init_test(&tmp);

    _ = try tmp.dir.statFile(".hvrt/config.voll");
    _ = try tmp.dir.statFile(".hvrt/repo.hvrt");
    _ = try tmp.dir.statFile(".hvrt/work_tree_state.sqlite");
}

test "invoke with add sub-command" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try setup_init_test(&tmp);

    const before_stat = try tmp.dir.statFile(".hvrt/work_tree_state.sqlite");
    try setup_add_test(&tmp);
    const after_stat = try tmp.dir.statFile(".hvrt/work_tree_state.sqlite");

    try std.testing.expect(before_stat.size < after_stat.size);
}

test "invoke with commit sub-command" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try setup_init_test(&tmp);
    try setup_add_test(&tmp);

    const before_stat = try tmp.dir.statFile(".hvrt/repo.hvrt");
    try setup_commit_test(&tmp);
    const after_stat = try tmp.dir.statFile(".hvrt/repo.hvrt");

    std.log.debug("\nbefore_stat.size: {}\nafter_stat.size: {}\n\n", .{ before_stat.size, after_stat.size });
    try std.testing.expect(before_stat.size < after_stat.size);
}

test "invoke without args" {
    // TODO: disable failure on error message here. See:
    // https://github.com/ziglang/zig/issues/5738#issuecomment-1466902082
    const basic_args = [_][:0]const u8{"test_prog_name"};
    cmd.internalMain(std.testing.allocator, &basic_args) catch |err| {
        // const expected_error = error.ArgumentError;
        const expected_error = error.NotImplementedError;
        const actual_error_union: anyerror!void = err;
        try std.testing.expectError(expected_error, actual_error_union);
    };
}

test "invoke with unknown subcommand" {
    // TODO: disable failure on error message here. See:
    // https://github.com/ziglang/zig/issues/5738#issuecomment-1466902082
    const basic_args = [_][:0]const u8{ "test_prog_name", "blahblahblah" };
    cmd.internalMain(std.testing.allocator, &basic_args) catch |err| {
        // const expected_error = error.ArgumentError;
        const expected_error = error.ArgumentError;
        const actual_error_union: anyerror!void = err;
        try std.testing.expectError(expected_error, actual_error_union);
    };
}

test "invoke with unimplemented subcommand" {
    // TODO: disable failure on error message here. See:
    // https://github.com/ziglang/zig/issues/5738#issuecomment-1466902082
    const basic_args = [_][:0]const u8{ "test_prog_name", "cp" };
    cmd.internalMain(std.testing.allocator, &basic_args) catch |err| {
        // const expected_error = error.ArgumentError;
        const expected_error = error.NotImplementedError;
        const actual_error_union: anyerror!void = err;
        try std.testing.expectError(expected_error, actual_error_union);
    };
}

test "first commit parent must have `regular` parent type" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try setup_init_test(&tmp);

    const repo_db_path = try tmp.dir.realpathAlloc(test_alloc, ".hvrt/repo.hvrt");
    defer test_alloc.free(repo_db_path);

    const repo_db_pathz = try test_alloc.dupeZ(u8, repo_db_path);
    defer test_alloc.free(repo_db_pathz);

    const repo_db = try sqlite.DataBase.open(repo_db_pathz);
    defer repo_db.close() catch unreachable;

    const commit_parent_stmt_txt = sql.sqlite.repo.commit.commit_parent;
    const commit_stmt_txt = sql.sqlite.repo.commit.commit;
    const tree_blob_member_stmt_txt = sql.sqlite.repo.commit.tree_member;
    const tree_member_stmt_txt = sql.sqlite.repo.commit.tree_member;
    const tree_stmt_txt = sql.sqlite.repo.commit.tree;
    const tree_tree_member_stmt_txt = sql.sqlite.repo.commit.tree_tree_member;

    // db statements
    const commit_stmt = try sqlite.Statement.prepare(repo_db, commit_stmt_txt);
    defer commit_stmt.finalize() catch unreachable;

    const commit_parent_stmt = try sqlite.Statement.prepare(repo_db, commit_parent_stmt_txt);
    defer commit_parent_stmt.finalize() catch unreachable;

    const tree_stmt = try sqlite.Statement.prepare(repo_db, tree_stmt_txt);
    defer tree_stmt.finalize() catch unreachable;

    const tree_member_stmt = try sqlite.Statement.prepare(repo_db, tree_member_stmt_txt);
    defer tree_member_stmt.finalize() catch unreachable;

    const tree_blob_member_stmt = try sqlite.Statement.prepare(repo_db, tree_blob_member_stmt_txt);
    defer tree_blob_member_stmt.finalize() catch unreachable;

    const tree_tree_member_stmt = try sqlite.Statement.prepare(repo_db, tree_tree_member_stmt_txt);
    defer tree_tree_member_stmt.finalize() catch unreachable;

    // TODO: attempt to insert a merge parent other than `regular`
    // and ensure it returns an error.

    // std.testing.expectError(anyerror{}, null);

    // std.log.debug("\nbefore_stat.size: {}\nafter_stat.size: {}\n\n", .{ before_stat.size, after_stat.size });
    // try std.testing.expect(before_stat.size < after_stat.size);
}
