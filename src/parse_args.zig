const std = @import("std");
const c = @import("c.zig");

const log = std.log.scoped(.parse_args);

pub const Command = enum {
    // i.e. no subcommand given
    global,

    // subcommands
    add,
    commit,
    cp,
    init,
    mv,
    rm,

    pub fn notImplemented(cmd: Command) !void {
        log.warn("Sub-command not implemented yet: {s}.\n", .{@tagName(cmd)});
        return error.NotImplementedError;
    }
};

pub const Args = struct {
    arena_ptr: *std.heap.ArenaAllocator,

    command: Command,
    repo_dirZ: [:0]const u8,
    verbose: i4 = 0,
    add_files: []const [:0]const u8,

    // On successful return, the caller must call `deinit` on the returned
    // `Args` object when it is no longer needed, otherwise memory will be
    // leaked.
    pub fn parseArgs(gpa: std.mem.Allocator, args: []const [:0]const u8) !Args {
        const arena_ptr = try gpa.create(std.heap.ArenaAllocator);
        arena_ptr.* = std.heap.ArenaAllocator.init(gpa);
        const arena_alloc = arena_ptr.allocator();
        errdefer {
            arena_ptr.deinit();
            gpa.destroy(arena_ptr);
        }

        // TODO: invoke ketopt here
        for (args[1..], 1..) |arg, i| {
            _ = arg;
            _ = i;
        }

        // if (args.len < 2) {
        //     log.warn("No sub-command given.\n", .{});
        //     return error.ArgumentError;
        // }

        const sub_cmd = if (args.len < 2) "global" else args[1];

        const cmd_enum_opt = std.meta.stringToEnum(Command, sub_cmd);
        if (cmd_enum_opt) |cmd_enum| {
            const repo_dir = if (args.len > 2) try std.fs.realpathAlloc(gpa, args[2]) else try std.process.getCwdAlloc(gpa);
            defer gpa.free(repo_dir);
            const repo_dirZ = try arena_alloc.dupeZ(u8, repo_dir);

            // For .add command
            const files_slice = if (args.len > 3) args[3..] else &.{};

            // Copy files, since there is no guarantee that the original slice
            // will stay around for the duration of this Args object.
            const files_copy = try arena_alloc.alloc([:0]const u8, files_slice.len);
            for (files_slice, 0..) |f, i| {
                files_copy[i] = try arena_alloc.dupeZ(u8, f);
            }

            return Args{
                .arena_ptr = arena_ptr,
                .command = cmd_enum,
                .repo_dirZ = repo_dirZ,
                .add_files = files_copy,
            };
        } else {
            log.warn("Unknown sub-command given: {s}\n", .{sub_cmd});
            return error.ArgumentError;
        }
    }

    // This must be called or memory will be leaked.
    pub fn deinit(self: Args) void {
        const child_allocator = self.arena_ptr.child_allocator;
        self.arena_ptr.deinit();
        child_allocator.destroy(self.arena_ptr);
    }
};
