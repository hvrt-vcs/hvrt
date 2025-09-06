const std = @import("std");
const allyouropt = @import("allyouropt.zig");

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
        return error.NotImplemented;
    }
};

pub const CommandOpts = union(Command) {
    // i.e. no subcommand given
    global: GlobalParsedOpts,

    // subcommands
    add: AddParsedOpts,
    commit: CommitParsedOpts,
    cp: bool,
    init: InitParsedOpts,
    mv: bool,
    rm: bool,

    pub fn notImplemented(cmd: CommandOpts) !void {
        log.warn("Sub-command not implemented yet: {s}.\n", .{@tagName(cmd)});
        return error.NotImplemented;
    }
};

const GlobalOpts: []const allyouropt.Opt = &.{
    .{
        .name = "help",
        .short_flags = "h",
        .long_flags = &.{"help"},
    },
    .{
        .name = "verbose",
        .short_flags = "v",
        .long_flags = &.{"verbose"},
    },
    .{
        .name = "version",
        .short_flags = "V",
        .long_flags = &.{"version"},
    },
    .{
        // Set the current working directory
        .name = "cwd",
        .short_flags = "C",
        .takes_arg = true,
    },
    .{
        // Set the work tree
        .name = "work-tree",
        .long_flags = &.{"work-tree"},
        .takes_arg = true,
    },
};

pub const GlobalParsedOpts = struct {
    const Self = @This();

    // Toggles
    help: bool = false,
    version: bool = false,

    // counted
    verbose: u3 = 0,

    // optional and take args
    cwd: ?[]const u8 = null,
    work_tree: ?[]const u8 = null,

    pub fn get_work_tree(self: Self) []const u8 {
        return self.work_tree orelse ".";
    }

    /// Parse all global args and return any unconsumed arguments.
    pub fn iter_opts(self: *Self, args_sans_prog_name: []const []const u8) ![]const []const u8 {
        var opt_iter_global = allyouropt.OptIterator{
            .args = args_sans_prog_name,
            .opt_defs = GlobalOpts,
        };

        while (opt_iter_global.next()) |o| {
            log.debug("What is the next option? {any}\n\n", .{o});
            try self.consume_opt(o);
        }

        const remaining_args = opt_iter_global.remaining_args();
        return remaining_args;
    }

    pub fn consume_opt(self: *Self, popt: allyouropt.ParsedOpt) !void {
        if (std.mem.eql(u8, popt.opt.name, "help")) {
            self.help = true;
        } else if (std.mem.eql(u8, popt.opt.name, "version")) {
            self.version = true;
        } else if (std.mem.eql(u8, popt.opt.name, "verbose")) {
            self.verbose +|= 1;
        } else if (std.mem.eql(u8, popt.opt.name, "cwd")) {
            self.cwd = popt.value;
        } else if (std.mem.eql(u8, popt.opt.name, "work-tree")) {
            self.work_tree = popt.value;
        } else {
            log.warn("Unknown option given: {s}", .{popt.opt.name});
            return error.UnknownOpt;
        }
    }

    pub fn finalize_opts(self: *Self, gpa: std.mem.Allocator) !void {
        self.work_tree = if (self.work_tree) |wt| try std.fs.realpathAlloc(gpa, wt) else try std.process.getCwdAlloc(gpa);
    }

    /// Walk the parent hierarchy until the repo root is found.
    /// Return `error.NoRepoRootFound` on failure.
    pub fn find_work_tree_root(self: Self, gpa: std.mem.Allocator) ![]const u8 {
        var cur_wt_opt: ?[]const u8 = self.work_tree;
        var mem_buf2: [1024 * 32]u8 = undefined;
        var fba_state2 = std.heap.FixedBufferAllocator.init(&mem_buf2);
        const fba_alloc2 = fba_state2.allocator();
        while (cur_wt_opt) |cur_wt| {
            fba_state2.reset();
            const maybe_wt_root = try std.fs.path.join(fba_alloc2, &.{ cur_wt, ".hvrt/work_tree_state.sqlite" });
            var wt_db_file = std.fs.openFileAbsolute(maybe_wt_root, .{}) catch {
                // This will eventually return null if/when we hit root (i.e. '/')
                cur_wt_opt = std.fs.path.dirname(cur_wt);
                continue;
            };
            wt_db_file.close();

            return try gpa.dupe(u8, cur_wt);
        }

        log.warn("Does not appear to be within a work tree: {?s}", .{self.work_tree});
        return error.NoRepoRootFound;
    }
};

const CommitOpts: []const allyouropt.Opt = &.{
    .{
        // Set the message for the commit
        .name = "message",
        .short_flags = "m",
        .long_flags = &.{"message"},
        .takes_arg = true,
    },
};

pub const CommitParsedOpts = struct {
    const Self = @This();

    // optional and take args
    message: ?[]const u8 = null,

    pub fn get_message(self: Self) ![]const u8 {
        if (self.message) |message| {
            // Caller set message as an opt, so return that.
            return message;
        } else {
            // TODO: implement calling the user's editor of choice with a
            // temporary file and then return it's contents.
            //
            // Probably do something similar to $GIT_DIR/COMMIT_EDITMSG so that
            // the message is saved if a crash happens for some reason:
            // https://git-scm.com/docs/git-commit#Documentation/git-commit.txt-GITDIRCOMMITEDITMSG
            log.warn("This needs to implement using an external editor to set commit message.\n", .{});
            return error.NotImplemented;
        }
    }

    /// Parse all `commit` subcommand args and return any unconsumed arguments.
    pub fn iter_opts(self: *Self, args_sans_prog_name: []const []const u8) ![]const []const u8 {
        var opt_iter_subcommand = allyouropt.OptIterator{
            .args = args_sans_prog_name,
            .opt_defs = CommitOpts,
        };

        while (opt_iter_subcommand.next()) |o| {
            log.debug("What is the next option? {any}\n\n", .{o});
            try self.consume_opt(o);
        }

        const remaining_args = opt_iter_subcommand.remaining_args();
        return remaining_args;
    }

    pub fn consume_opt(self: *Self, popt: allyouropt.ParsedOpt) !void {
        if (std.mem.eql(u8, popt.opt.name, "message")) {
            self.message = popt.value;
        } else {
            log.warn("Unknown option given: {s}", .{popt.opt.name});
            return error.UnknownOpt;
        }
    }
};

const AddOpts: []const allyouropt.Opt = &.{
    .{
        .name = "force",
        .short_flags = "f",
        .long_flags = &.{"force"},
    },
};

pub const AddParsedOpts = struct {
    const Self = @This();

    force: bool = false,

    /// Parse all `commit` subcommand args and return any unconsumed arguments.
    pub fn iter_opts(self: *Self, args_sans_prog_name: []const []const u8) ![]const []const u8 {
        var opt_iter_subcommand = allyouropt.OptIterator{
            .args = args_sans_prog_name,
            .opt_defs = CommitOpts,
        };

        while (opt_iter_subcommand.next()) |o| {
            log.debug("What is the next option? {any}\n\n", .{o});
            try self.consume_opt(o);
        }

        const remaining_args = opt_iter_subcommand.remaining_args();
        return remaining_args;
    }

    pub fn consume_opt(self: *Self, popt: allyouropt.ParsedOpt) !void {
        if (std.mem.eql(u8, popt.opt.name, "force")) {
            self.force = true;
        } else {
            log.warn("Unknown option given: {s}", .{popt.opt.name});
            return error.UnknownOpt;
        }
    }
};

const InitOpts: []const allyouropt.Opt = &.{
    .{
        .name = "initial-branch",
        .short_flags = "b",
        .long_flags = &.{"initial-branch"},
    },
};

pub const InitParsedOpts = struct {
    const Self = @This();

    initial_branch: ?[]const u8 = null,

    /// Parse all `commit` subcommand args and return any unconsumed arguments.
    pub fn iter_opts(self: *Self, args_sans_prog_name: []const []const u8) ![]const []const u8 {
        var opt_iter_subcommand = allyouropt.OptIterator{
            .args = args_sans_prog_name,
            .opt_defs = CommitOpts,
        };

        while (opt_iter_subcommand.next()) |o| {
            log.debug("What is the next option? {any}\n\n", .{o});
            try self.consume_opt(o);
        }

        const remaining_args = opt_iter_subcommand.remaining_args();
        return remaining_args;
    }

    pub fn consume_opt(self: *Self, popt: allyouropt.ParsedOpt) !void {
        if (std.mem.eql(u8, popt.opt.name, "initial-branch")) {
            self.initial_branch = popt.value;
        } else {
            log.warn("Unknown option given: {s}", .{popt.opt.name});
            return error.UnknownOpt;
        }
    }
};

pub const Args = struct {
    arena_ptr: *std.heap.ArenaAllocator,

    command: CommandOpts,
    verbose: i4 = 0,
    trailing_args: []const []const u8,
    gpopts: GlobalParsedOpts,

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

        const sans_prog_name = if (args.len > 0) args[1..] else &.{};

        var gopts: GlobalParsedOpts = .{};

        const remaining_args = try gopts.iter_opts(sans_prog_name);
        try gopts.finalize_opts(arena_alloc);

        const sub_cmd = if (remaining_args.len > 0) remaining_args[0] else "global";

        const cmd_enum_opt = std.meta.stringToEnum(Command, sub_cmd);

        if (cmd_enum_opt) |cmd_enum| {

            // TODO: parse subcommand opts

            const trailing_args = if (remaining_args.len > 1) remaining_args[1..] else &.{};

            if (trailing_args.len > 0) {
                log.debug("What is Args.trailing_args[0]? {s}\n\n", .{trailing_args[0]});
            }

            var self = Args{
                .arena_ptr = arena_ptr,
                .command = .{ .global = gopts },
                .trailing_args = trailing_args,
                .gpopts = gopts,
            };

            switch (cmd_enum) {
                .global => {
                    self.command = .{ .global = gopts };
                },
                .init => {
                    var popts: InitParsedOpts = .{};
                    self.trailing_args = try popts.iter_opts(trailing_args);
                    self.command = .{ .init = popts };
                },
                .add => {
                    var popts: AddParsedOpts = .{};
                    self.trailing_args = try popts.iter_opts(trailing_args);
                    self.command = .{ .add = popts };
                },
                .commit => {
                    var popts: CommitParsedOpts = .{};
                    self.trailing_args = try popts.iter_opts(trailing_args);
                    self.command = .{ .commit = popts };
                },
                .mv => {
                    self.command = .{ .mv = true };
                },
                .cp => {
                    self.command = .{ .cp = true };
                },
                .rm => {
                    self.command = .{ .rm = true };
                },
            }

            return self;
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

test "refAllDeclsRecursive" {
    std.testing.refAllDeclsRecursive(@This());
}
