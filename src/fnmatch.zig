const std = @import("std");
const fspath = std.fs.path;

// This is not a regex, but we can use similar concepts here. To start, we'll make a state machine:
// * https://swtch.com/~rsc/regexp/regexp1.html
// * https://swtch.com/~rsc/regexp/regexp2.html
// * https://swtch.com/~rsc/regexp/regexp3.html

pub const FnMatchState = union(enum) {
    /// Sorted set of all characters that can match for the class
    char_class: []const u21,
    exact: u21,
    match: void,
    start: void,
    wild_many: void,
    wild_single: void,
};

pub const StateNode = struct {
    state: FnMatchState,
    next_states: std.ArrayList(*StateNode),
};

const FnMatchParser = struct {
    const ParseState = enum(u21) {
        char_class_open = '[',
        escape = '\\',
        literal = 0,
        range = '-',
        wild_many = '*',
        wild_single = '?',
    };

    pub fn parse(gpa: std.mem.Allocator, arena: std.mem.Allocator, pattern: []const u8) !*StateNode {

        // Create a local arena for the parsing process. On success, all data
        // is copied to the arena passed into the function.
        var larena_state = std.heap.ArenaAllocator.init(gpa);
        defer larena_state.deinit();
        const larena = larena_state.allocator();

        var initial_state = try arena.create(StateNode);
        initial_state.* = .{ .state = .{ .start = void{} }, .next_states = std.ArrayList(*StateNode).init(larena) };
        _ = &initial_state;
        var current_state = initial_state;
        _ = &current_state;

        // If the rune doesn't parse to a possible state, it must
        // be a unicode code point, meaning it is a rune literal.
        var utf8_view = try std.unicode.Utf8View.init(pattern);
        var utf8_iter = utf8_view.iterator();

        var current_rune = utf8_iter.nextCodepoint() orelse return error.ParseError;
        var parse_state = std.meta.intToEnum(ParseState, current_rune) catch ParseState.literal;
        while (utf8_iter.nextCodepoint()) |next_rune| {
            switch (parse_state) {
                .char_class_open => {
                    const state_ptr = try arena.create(StateNode);
                    state_ptr.* = try parseCharclass(larena, current_state, current_rune);
                    current_state = state_ptr;
                },
                .escape => {
                    // Force the next iteration to treat the `prior_rune` as a
                    // literal, no matter what the rune it actually is.
                    parse_state = ParseState.literal;
                    current_rune = next_rune;
                    continue;
                },
                .literal => {
                    const state_ptr = try arena.create(StateNode);
                    state_ptr.* = try parseLiteral(larena, current_state, current_rune);
                    current_state = state_ptr;
                },
                .wild_many => {
                    const state_ptr = try arena.create(StateNode);
                    state_ptr.* = try parseWildMany(larena, current_state, current_rune);
                    current_state = state_ptr;
                },
                .wild_single => {
                    const state_ptr = try arena.create(StateNode);
                    state_ptr.* = try parseWildSingle(larena, current_state, current_rune);
                    current_state = state_ptr;
                },
                // Ranges should only be possible within char classes
                .range => return error.ParseError,
            }

            // If the rune doesn't parse to a possible state, it must be a
            // unicode code point, meaning it is a rune literal.
            parse_state = std.meta.intToEnum(ParseState, next_rune) catch ParseState.literal;
            current_rune = next_rune;
        }
    }

    pub fn parseLiteral(larena: std.mem.Allocator, from_state: *StateNode, rune: u21) !StateNode {
        _ = rune; // autofix
        _ = from_state; // autofix
        _ = larena; // autofix
    }

    pub fn parseCharclass(larena: std.mem.Allocator, from_state: *StateNode, rune: u21) !StateNode {
        _ = rune; // autofix
        _ = from_state; // autofix
        _ = larena; // autofix
    }

    pub fn parseRange(larena: std.mem.Allocator, from_state: *StateNode, rune: u21) !StateNode {
        _ = rune; // autofix
        _ = from_state; // autofix
        _ = larena; // autofix
    }

    pub fn parseWildMany(larena: std.mem.Allocator, from_state: *StateNode, rune: u21) !StateNode {
        _ = rune; // autofix
        _ = from_state; // autofix
        _ = larena; // autofix
    }

    pub fn parseWildSingle(larena: std.mem.Allocator, from_state: *StateNode, rune: u21) !StateNode {
        _ = rune; // autofix
        _ = from_state; // autofix
        _ = larena; // autofix
    }
};

pub const FnMatcher = struct {
    initial_state: *StateNode,
    alloc: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,

    pub fn init(gpa: std.mem.Allocator, pattern: []const u8) !FnMatcher {
        var arena_state = std.heap.ArenaAllocator.init(gpa);
        errdefer arena_state.deinit();
        const arena = arena_state.allocator();

        const initial_state = try FnMatchParser.parse(gpa, arena, pattern);
        return .{ .initial_state = initial_state, .arena = arena_state };
    }

    pub fn deinit(self: *FnMatcher) void {
        self.arena.deinit();
    }

    pub fn match(self: FnMatcher, string: []const u8) bool {
        var current_state = self.initial_state;
        _ = &current_state;

        // If a string isn't valid utf, then it doesn't match. Just return false on error.
        var utf_view = std.unicode.Utf8View.init(string) catch return false;
        var utf8_iter = utf_view.iterator();
        while (utf8_iter.nextCodepoint()) |rune| {
            _ = rune;
        }
    }
};
