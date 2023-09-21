const std = @import("std");
const assert = std.debug.assert;
pub const Pos = @Vector(2, i32);

// TODO: for undo, instead of doing work to reverse things like noun replacements, could just replay all inputs minus one. is anything random? 
pub const Level = struct {
    entities: std.ArrayList(Entity),
    actionHistory: std.ArrayList(Input),  // TODO: include in save file. 
    rules: Rules,
    size: Pos,
    rulesDirty: bool = false,
    pub fn init(alloc: std.mem.Allocator, size: Pos) Level {
        return .{
            .entities = std.ArrayList(Entity).init(alloc),
            .actionHistory = std.ArrayList(Input).init(alloc),
            .rules = Rules.init(),
            .size = size,
        };
    }

    pub fn handleInput(self: *Level, in: Input) !void {
        switch (in) {
            .Left => self.movePlayer(Dir.LEFT),
            .Right => self.movePlayer(Dir.RIGHT),
            .Up => self.movePlayer(Dir.UP),
            .Down => self.movePlayer(Dir.DOWN),
            .Wait => {},
        }
        self.tick();
        // TODO: if you already lost, dont keep recording moves that do nothing. they cluter the undo history. 
        //       would be fixed if tracked transations that actually made a change instead. 
        try self.actionHistory.append(in);
    }

    pub fn tick(self: *Level) void {
        if (self.rulesDirty) {
            self.updateRules();
            self.rulesDirty = false;
        }
        // TODO: X is MOVE
        // TODO: this gets called when you move or wait
    }

    pub fn movePlayer(self: *Level, dir: Pos) void {
        for (self.entities.items) |*e| {
            switch (e.block) {
                .Object => |noun| {
                    if (self.rules.is(noun, .You)) {
                        _ = self.resolveMove(e, dir);
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
                // We need to push the thing out of the way. 
                if (!self.resolveMove(other, dir)) {
                    // Something down the line was blocked, so nobody can move. 
                    return false;
                }
            } else {
                // Not stop and not push, so just pass through. 
            }   
        }

        // Nothing down the line stopped us, so its safe to update our position. 
        e.pos += dir;
        if (e.block.isText()) {
            self.rulesDirty = true;
        }
        return true;
    }

    // Also does noun replacements. // TODO: that's a special type of transaction. 
    // TOOD: needs to be deterministic over entity order. update a new rules struct and then swap at the end. and then do all noun swaps. tick somewhere in there. test correct order  
    pub fn updateRules(self: *Level) void {
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

    pub fn deinit(self: *Level) void {
        self.entities.deinit();
        self.actionHistory.deinit();
    }

    pub fn clone(self: Level, alloc: std.mem.Allocator) !Level {
        var w = Level.init(alloc, self.size);
        w.entities = try self.entities.clone();
        w.actionHistory = try w.actionHistory.clone();
        w.updateRules();
        return w;

    }

    // TODO: sad slow noises. maybe have a bit field showing which squares have a dude in them. empty is the common case. 
    // TODO: a square can have multiple dudes (NOUN is float). 
    // Unsafe. Must update rulesDirty if mutate through this. Also don't store the pointer.
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

    pub fn addEntity(self: *Level, pos: Pos, block: Block) !void {
        if (block.isText()) {
            self.rulesDirty = true;
        }
        try self.entities.append(.{ .pos=pos, .block=block });
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
            .Object => |noun| self.is(noun, .Push) or self.is(noun, .You),
            else => true,
        };
    }

    // TODO: needs to know the mover entity as well for layers (IS FLOAT)
    pub fn isStop(self: Rules, e: Entity) bool {
        return switch (e.block) {
            .Object => |noun| self.is(noun, .Stop),
            else => false,
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

pub const Input = enum {
    Left,
    Right,
    Up,
    Down,
    Wait
};

pub const Entity = struct {
    block: Block,
    pos: Pos,
};

pub const Block = union(BlockType) {
    Noun: Noun,
    State: State,
    Object: Noun,
    Is,
    And,

    pub fn isText(self: Block) bool {
        return self == @field(Block, "Object");
    }


    pub fn name(self: Block) []const u8 {
        return switch (self) {
            .Noun => |noun| @tagName(noun),
            .Object => |noun| @tagName(noun),
            .State => |state| @tagName(state),
            else => @tagName(self),
        };
    }
};

pub const BlockType = enum {
    Noun,
    State,
    Object,
    Is,
    And,
};

pub const Noun = enum {
    Baba,
    Rock,
    Wall,
    Flag,
};

pub const State = enum {
    You,
    Push,
    Stop,
    Move,
    Win,
};

pub const Dir = struct {
    pub const UP: Pos = .{ 0, -1 };
    pub const DOWN: Pos = .{ 0, 1 };
    pub const LEFT: Pos = .{ -1, 0 };
    pub const RIGHT: Pos = .{ 1, 0 };
};
