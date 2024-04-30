const std = @import("std");
const fspath = std.fs.path;
const Dir = std.fs.Dir;

const sqlite = @import("sqlite.zig");
const sql = @import("sql.zig");

const hvrt_dirname: [:0]const u8 = ".hvrt";
const repo_db_name: [:0]const u8 = "repo.hvrt";
const work_tree_db_name: [:0]const u8 = "work_tree_state.sqlite";
const default_config_name: [:0]const u8 = "config.toml";
const default_config: [:0]const u8 = @embedFile("embedded/default.toml");
const default_branch: [:0]const u8 = "master";

const version: [:0]const u8 = @embedFile("embedded/VERSION.txt");

/// It is the responsibility of the caller of `init` to deallocate and
/// deinit dir_path and alloc, if necessary.
pub fn init(alloc: std.mem.Allocator, repo_path: [:0]const u8) !void {
    var repo_dir = try std.fs.openDirAbsolute(repo_path, .{});
    defer repo_dir.close();

    // fails if directory already exists
    var hvrt_dir = try repo_dir.makeOpenPath(hvrt_dirname, .{});
    errdefer repo_dir.deleteTree(hvrt_dirname) catch unreachable;
    defer hvrt_dir.close();

    // Deferring file close until the end of this function has the added
    // benefit of holding an exclusive file lock for the duration of the
    // function call.
    var config_file = try hvrt_dir.createFile(default_config_name, .{ .exclusive = true, .lock = .exclusive });
    defer config_file.close();
    _ = try config_file.write(default_config);

    // Worktree
    const wt_db_path_parts = [_][]const u8{ repo_path, hvrt_dirname, work_tree_db_name };
    const wt_db_path = try fspath.joinZ(alloc, &wt_db_path_parts);
    defer alloc.free(wt_db_path);
    std.log.debug("what is wt_db_path: {s}\n", .{wt_db_path});

    const wt_sql = sql.sqlite.work_tree orelse unreachable;
    try initDatabase(wt_db_path, "worktree_init", wt_sql);

    // Repo
    const repo_db_path_parts = [_][]const u8{ repo_path, hvrt_dirname, repo_db_name };
    const repo_db_path = try fspath.joinZ(alloc, &repo_db_path_parts);
    defer alloc.free(repo_db_path);

    // TODO: add postgres support
    const repo_sql = sql.sqlite.repo orelse unreachable;
    try initDatabase(repo_db_path, "repo_init", repo_sql);
}

fn initDatabase(db_uri: [:0]const u8, tx_name: [:0]const u8, sqlfiles: anytype) !void {
    const db = try sqlite.DataBase.open(db_uri);
    defer db.close() catch unreachable;

    var tx_ok = true;
    const tx = try sqlite.Transaction.init(db, tx_name);
    defer if (tx_ok) tx.commit() catch unreachable;
    errdefer tx.rollback() catch unreachable;
    errdefer tx_ok = false;

    try db.exec(sqlfiles.init.tables);

    // Version
    const prepared_stmt1 = try sqlite.Statement.prepare(db, sqlfiles.init.version);
    defer prepared_stmt1.finalize() catch unreachable;

    try prepared_stmt1.bind(1, false, version);
    try prepared_stmt1.auto_step();

    // default branch1
    const prepared_stmt2 = try sqlite.Statement.prepare(db, sqlfiles.init.branch1);
    defer prepared_stmt2.finalize() catch unreachable;

    try prepared_stmt2.bind(1, false, default_branch);
    try prepared_stmt2.auto_step();

    // default branch2
    const prepared_stmt3 = try sqlite.Statement.prepare(db, sqlfiles.init.branch2);
    defer prepared_stmt3.finalize() catch unreachable;

    try prepared_stmt3.bind(1, false, default_branch);
    try prepared_stmt3.auto_step();
}
