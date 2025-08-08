const std = @import("std");
const fspath = std.fs.path;
const Dir = std.fs.Dir;

const log = std.log.scoped(.add);

const hvrt_dirname: [:0]const u8 = ".hvrt";
const work_tree_db_name: [:0]const u8 = "work_tree_state.sqlite";

test "refAllDeclsRecursive" {
    std.testing.refAllDeclsRecursive(@This());
}

test "url parse" {
    const uri_string = "file:.hvrt/repo.hvrt";

    const uri = try std.Uri.parse(uri_string);

    std.debug.print("What is the uri scheme? {s}\n\n", .{uri.scheme});
    std.debug.print("What is the uri path? {any}\n\n", .{uri.path});
}
