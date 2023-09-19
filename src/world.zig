const std = @import("std");
pub const Pos = @Vector(2, i32);

pub const Level = struct {
    entities: std.ArrayList(Entity),
    rules: Rules,
    size: Pos,
    pub fn init(alloc: std.mem.Allocator, size: Pos) Level {
        return .{
            .entities = std.ArrayList(Entity).init(alloc),
            .rules = Rules.init(),
            .size = size,
        };
    }

    pub fn calculateRules(self: *Level) void {
        for (self.entities.items) |e| {
            switch (e.block) {
                .Is => {
                    self.updateFromIs(e.pos, Dir.UP);
                    self.updateFromIs(e.pos, Dir.LEFT);
                },
                else => {}
            }
        }
    }

    pub fn updateFromIs(self: *Level, isBlockPos: Pos, dir: Pos) void {
        if (self.getEntity(isBlockPos + dir)) |before| {
            switch (before.block) {
                .Noun => |beforeNoun| {
                    if (self.getEntity(isBlockPos - dir)) |after| {
                        switch (after.block) {
                            .Noun => |afterNoun| {
                                self.swapNouns(beforeNoun, afterNoun);
                            },
                            .State => |afterState| {
                                self.rules.set(beforeNoun, afterState);
                            },
                            else => {}
                        }
                    }
                },
                else => {}
            }
        }
    }

    pub fn swapNouns(self: *Level, from: Noun, to: Noun) void {
        for (self.entities.items) |*e| {
            switch (e.block) {
                .Object => |*found| {
                    if (found.* == from) {
                        found.* = to;
                    }
                },
                else => {}
            }
        }
    }

    // TODO: sad slow noises. maybe have a bit field showing which squares have a dude in them. 
    // TODO: a square can have multiple dudes (NOUN is float). 
    pub fn getEntity(self: *Level, pos: Pos) ?*Entity {
        for (self.entities.items) |*e| {
            if (@reduce(.And, e.pos == pos)) {
                return e;
            }
        }
        return null;
    }
};

pub const Rules = struct {
    states: std.EnumMap(Noun, std.EnumSet(State)), 

    pub fn is(self: Rules, noun: Noun, state: State) bool {
        return self.states.get(noun).?.contains(state);
    }

    pub fn set(self: *Rules, noun: Noun, state: State) void {
        self.states.getPtr(noun).?.insert(state);
    }

    pub fn clear(self: *Rules) void {
        inline for (comptime std.enums.values(Noun)) |noun| {
            self.states.put(noun, std.EnumSet(State).initEmpty());
        }
    }

    pub fn init() Rules {
        var self: Rules = .{ .states = .{} };
        self.clear();
        return self;
    }
};

pub const Entity = struct {
    block: Block,
    pos: Pos
};

pub const Block = union(BlockType) {
    Noun: Noun,
    State: State,
    Object: Noun,
    Is,
    And
};

pub const BlockType = enum {
    Noun,
    State,
    Object,
    Is,
    And
};

pub const Noun = enum {
    Baba,
    Rock,
    Wall
};

pub const State = enum {
    You,
    Push,
};

pub const Dir = struct {
    pub const UP: Pos = .{ 0, 1 };
    pub const DOWN: Pos = .{ 0, -1 };
    pub const LEFT: Pos = .{ -1, 0 };
    pub const RIGHT: Pos = .{ 1, 0 };
};

const expectEq = std.testing.expectEqual;
test "world repr sanity" {
    var w = Level.init(std.heap.c_allocator, .{ 20, 30 });

    try expectEq(w.rules.is(.Baba, .You), false);
    w.rules.set(.Baba, .You);
    try expectEq(w.rules.is(.Baba, .You), true);
    w.rules.clear();
    try expectEq(w.rules.is(.Baba, .You), false);

    try expectEq(w.getEntity(.{ 0, 0 }), null);
    try w.entities.append(.{ .pos = .{ 1, 0 }, .block = .{ .Object = .Rock }});
    try w.entities.append(.{ .pos = .{ 0, 0 }, .block = .{ .Object = .Baba }});
    try w.entities.append(.{ .pos = .{ 1, 10 }, .block = .{ .Object = .Wall }});
    try w.entities.append(.{ .pos = .{ 5, 0 }, .block = .{ .State = .You }});
    try expectEq(w.getEntity(.{ 0, 0 }).?.block, .{ .Object = .Baba });

    try w.entities.append(.{ .pos = .{ 1, 20 }, .block = .{ .Noun = .Baba }});
    w.swapNouns(.Baba, .Wall);
    try expectEq(w.getEntity(.{ 0, 0 }).?.block, .{ .Object = .Wall });
    try expectEq(w.getEntity(.{ 1, 20 }).?.block, .{ .Noun = .Baba });  // swapNouns doesn't effect the words. 
    w.swapNouns(.Wall, .Baba);
    try expectEq(w.getEntity(.{ 0, 0 }).?.block, .{ .Object = .Baba });
    try expectEq(w.getEntity(.{ 1, 10 }).?.block, .{ .Object = .Baba });

    try w.entities.append(.{ .pos = .{ 2, 20 }, .block = .Is});
    try w.entities.append(.{ .pos = .{ 3, 20 }, .block = .{ .Noun = .Wall }});
    w.calculateRules();
    try expectEq(w.getEntity(.{ 0, 0 }).?.block, .{ .Object = .Wall });
    try expectEq(w.getEntity(.{ 1, 10 }).?.block, .{ .Object = .Wall });

    // const save = @import("save.zig");
    // const data = try save.saveLevel(w, std.heap.c_allocator);
    // std.debug.print("{!s}", .{data});
    // const w2 = try save.loadLevel(data, std.heap.c_allocator);
    // std.debug.print("{!s}", .{ save.saveLevel(w2, std.heap.c_allocator) });
}
