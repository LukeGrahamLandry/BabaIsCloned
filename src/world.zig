const std = @import("std");
const assert = std.debug.assert;
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

    pub fn movePlayer(self: *Level, dir: Pos) void {
        for (self.entities.items) |*e| {
            switch (e.block) {
                .Object => |noun| {
                    if (self.rules.is(noun, .You)) {
                        if (!self.resolveMove(e, dir)) {
                            // Hit something, so can't go that way. 
                        }
                    }
                },
                else => {}
            }
            
        }
    }

    pub fn resolveMove(self: *Level, e: *Entity, dir: Pos) bool {
        if (self.offBoard(e.pos + dir)) {
            return false;
        }

        if (self.getEntity(e.pos + dir)) |other| {
            if (self.rules.isStop(other.*)) {
                return false;
            }
            if (self.rules.playerCanPush(other.*)) {
                if (!self.resolveMove(other, dir)) {
                    return false;
                }
            } else {
                // Not stop and not push, so just pass through. 
            }
            
        }

        e.pos += dir;
        return true;
    }

    pub fn calculateRules(self: *Level) void {
        self.rules.clear();
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
    
    pub fn onEdge(self: Level, pos: Pos) bool {
        return pos[0] == 0 or pos[1] == 0 or pos[0] == self.size[0]-1 or pos[1] == self.size[1]-1;
    }

    pub fn offBoard(self: Level, pos: Pos) bool {
        return pos[0] < 0 or pos[1] < 0 or pos[0] >= self.size[0] or pos[1] >= self.size[1];   
    }

    pub fn debugPrint(self: Level) void {
        var buf: [4096] u8 = undefined;
        var temp = std.heap.FixedBufferAllocator.init(&buf);
        const info = @import("save.zig").saveLevel(self, temp.allocator());
        std.debug.print("{!s}\n", .{info});
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

    pub fn playerCanPush(self: Rules, e: Entity) bool {
        return switch (e.block) {
            .Noun => true,
            .State => true,
            .Is => true,
            .And => true,
            .Object => |noun| self.is(noun, .Push) or self.is(noun, .You),
        };
    }

    // TODO: needs to know the mover entity as well for layers (IS FLOAT)
    pub fn isStop(self: Rules, e: Entity) bool {
        return switch (e.block) {
            .Noun => false,
            .State => false,
            .Is => false,
            .And => false,
            .Object => |noun| self.is(noun, .Stop),
        };
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
    Stop,
};

pub const Dir = struct {
    pub const UP: Pos = .{ 0, -1 };
    pub const DOWN: Pos = .{ 0, 1 };
    pub const LEFT: Pos = .{ -1, 0 };
    pub const RIGHT: Pos = .{ 1, 0 };
};

