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
        return error.NotImplementedError;
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
    // Toggles
    help: bool = false,
    version: bool = false,

    // counted
    verbose: u3 = 0,

    // optional and take args
    cwd: ?[]const u8 = null,
    work_tree: ?[]const u8 = null,

    pub fn get_work_tree(self: GlobalParsedOpts) []const u8 {
        return self.work_tree orelse ".";
    }

    pub fn consume_opt(self: *GlobalParsedOpts, popt: allyouropt.ParsedOpt) !void {
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

    pub fn finalize_opts(self: *GlobalParsedOpts, arena_alloc: std.mem.Allocator) !void {
        self.work_tree = if (self.work_tree) |wt| try std.fs.realpathAlloc(arena_alloc, wt) else try std.process.getCwdAlloc(arena_alloc);
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
    // optional and take args
    message: ?[]const u8 = null,

    pub fn consume_opt(self: *GlobalParsedOpts, popt: allyouropt.ParsedOpt) !void {
        if (std.mem.eql(u8, popt.opt.name, "message")) {
            self.message = popt.value;
        } else {
            log.warn("Unknown option given: {s}", .{popt.opt.name});
            return error.UnknownOpt;
        }
    }
};

pub const Args = struct {
    arena_ptr: *std.heap.ArenaAllocator,

    command: Command,
    repo_dirZ: [:0]const u8,
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

        var self = Args{
            .arena_ptr = arena_ptr,
            .command = .global,
            .repo_dirZ = &.{},
            .trailing_args = &.{},
            .gpopts = .{},
        };

        const sans_prog_name = if (args.len > 0) args[1..] else &.{};

        var opt_iter_global = allyouropt.OptIterator{
            .args = sans_prog_name,
            .opt_defs = GlobalOpts,
        };

        var work_tree_opt: ?[]const u8 = null;

        while (opt_iter_global.next()) |o| {
            log.debug("What is the next option? {any}\n\n", .{o});
            try self.gpopts.consume_opt(o);

            if (std.mem.eql(u8, o.opt.name, "work-tree")) {
                work_tree_opt = o.value orelse unreachable;
            }
        }

        const remaining_args = opt_iter_global.remaining_args();

        const sub_cmd = if (remaining_args.len > 0) remaining_args[0] else "global";

        const cmd_enum_opt = std.meta.stringToEnum(Command, sub_cmd);

        if (cmd_enum_opt) |cmd_enum| {
            self.command = cmd_enum;
            try self.gpopts.finalize_opts(arena_alloc);

            // TODO: parse subcommand opts

            const trailing_args = if (remaining_args.len > 1) remaining_args[1..] else &.{};
            self.trailing_args = trailing_args;

            if (self.trailing_args.len > 0) {
                log.debug("What is Args.trailing_args[0]? {s}\n\n", .{self.trailing_args[0]});
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
