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
    wild_many: void,
    wild_single: void,
};

pub const StateNode = struct {
    state: FnMatchState,
    next_states: []*StateNode,
};

pub const FnMatcher = struct {
    initial_state: *StateNode,
    alloc: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,

    const ParseState = enum(u21) {
        char_class_open = '[',
        escape = '\\',
        literal = 0,
        range = '-',
        wild_many = '*',
        wild_single = '?',
    };

    pub fn init(alloc: std.mem.Allocator, pattern: []const u8) !FnMatcher {
        var char_class = std.ArrayList(u21).init(alloc);
        _ = &char_class;
        var utf_view = try std.unicode.Utf8View.init(pattern);
        var utf8_iter = utf_view.iterator();

        var parse_state = ParseState.literal;
        _ = &parse_state;
        while (utf8_iter.nextCodepoint()) |rune| {
            switch (parse_state) {
                .char_class_open => unreachable,
                .escape => unreachable,
                .literal => {
                    const state = std.meta.intToEnum(ParseState, rune) catch {};
                    _ = state;
                },
                .range => unreachable,
                .wild_many => unreachable,
                .wild_single => unreachable,
            }
        }
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
