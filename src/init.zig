const std = @import("std");
const fspath = std.fs.path;
const Dir = std.fs.Dir;

const sqlite = @import("sqlite.zig");
const sql = @import("sql.zig");

const hvrt_dirname = ".hvrt";
const work_tree_db_name = "work_tree_state.sqlite";
const default_config_name = "config.toml";
const default_config = @embedFile("embedded/default.toml");

const version = @embedFile("embedded/VERSION.txt");

/// It is the responsibility of the caller of `init` to deallocate and
/// deinit dir_path and alloc, if necessary.
pub fn init(alloc: std.mem.Allocator, repo_path: [:0]const u8) !void {

    // const path = try std.fs.path.join(alloc, .{ dir_path, ".hvrt" });
    const path_parts = [_][]const u8{ repo_path, hvrt_dirname };
    const hvrt_path = try fspath.joinZ(alloc, &path_parts);
    defer alloc.free(hvrt_path);

    // fails if directory already exists
    try std.fs.makeDirAbsolute(hvrt_path);
    const hvrt_dir = try std.fs.openDirAbsolute(hvrt_path, .{});

    // Deferring file close until the end of this function has the added
    // benefit of holding an exclusive file lock for the duration of the
    // function call.
    var config_file = try hvrt_dir.createFile(default_config_name, .{ .exclusive = true, .lock = .exclusive });
    defer config_file.close();
    _ = try config_file.write(default_config);

    const db_path_parts = [_][]const u8{ hvrt_path, work_tree_db_name };
    const db_path = try fspath.joinZ(alloc, &db_path_parts);
    defer alloc.free(db_path);
    std.debug.print("what is db_path: {s}\n", .{db_path});

    const db = try sqlite.DataBase.open(db_path);
    defer db.close() catch unreachable;

    const sqlfiles = sql.sqlite;

    try db.exec(sqlfiles.work_tree.init.tables);

    // Preparing a statement will only evaluate one statement (semicolon
    // terminated) at a time. So we can't just compile the whole init script
    // and run it. Will need to either split the script into multiple pieces,
    // or add some logic to iterate over the statements/detect when parameters
    // need to be bound. See link here for an example of this logic:
    // https://github.com/praeclarum/sqlite-net/issues/84
    const prepared_stmt1 = try sqlite.Statement.prepare(db, sqlfiles.work_tree.init.version);
    defer prepared_stmt1.finalize() catch unreachable;

    // Version
    try prepared_stmt1.bind_text(1, version);

    while (prepared_stmt1.step()) |rc| {
        _ = try rc.check(db);
    }

    std.debug.print("Did we insert the version?\n", .{});

    const prepared_stmt2 = try sqlite.Statement.prepare(db, sqlfiles.work_tree.init.branch);
    defer prepared_stmt2.finalize() catch unreachable;

    // default branch
    try prepared_stmt2.bind_text(1, "master");

    while (prepared_stmt2.step()) |rc| {
        _ = try rc.check(db);
    }

    std.debug.print("Did we insert the default branch name?\n", .{});
    // // default branch
    // try sqlite3_bind(prepared_stmt, 2, "master");

    // // stdout is for the actual output of your application, for example if you
    // // are implementing gzip, then only the compressed bytes should be sent to
    // // stdout, not any debugging messages.
    // const stdout_file = std.io.getStdOut().writer();
    // var bw = std.io.bufferedWriter(stdout_file);
    // const stdout = bw.writer();

    // try stdout.print("Run `zig build test` to run the tests.\n", .{});

    // try bw.flush(); // don't forget to flush!
}
