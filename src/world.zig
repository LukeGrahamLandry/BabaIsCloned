const std = @import("std");
const assert = std.debug.assert;
pub const Pos = @Vector(2, i32);

pub var frameArena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
pub var TEMP = frameArena.allocator();

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
            self.debugPrint();
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

        const blockers = self.getEntity(e.pos + dir);
        if (blockers.len > 0) {
            for (blockers) |other| {
                // You can push things that are stop. But otherwise, bail out. 
                if (self.rules.isStop(other.*) and !self.rules.playerCanPush(other.*)) {
                    return false;
                }
            }

            for (blockers) |other| {
                // If we have to push it, make sure it has somewhere to go. 
                // TODO: this is wrong! What happens if the first thing can move but second gets blocked? 
                if (self.rules.playerCanPush(other.*) and !self.resolveMove(other, dir)) {
                    // Something down the line was blocked, so nobody can move. 
                    return false;
                }
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

    // TODO: assert only one text per position. 
    pub fn updateFromIs(self: *Level, isBlockPos: Pos, dir: Pos) void {
        const beforeS = self.getEntity(isBlockPos + dir);
        for (beforeS) |before| {
            switch (before.block) {
                .Noun => |beforeNoun| {
                    const afterS = self.getEntity(isBlockPos - dir);
                    for (afterS) |after| {
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
        try w.copyFrom(self);
        return w;
    }

    pub fn copyFrom(self: *Level, other: Level) !void {
        self.entities.clearRetainingCapacity();
        self.actionHistory.clearRetainingCapacity();
        try self.entities.appendSlice(other.entities.items);
        try self.actionHistory.appendSlice(other.actionHistory.items);
        self.rules = other.rules;
        self.rulesDirty = other.rulesDirty;
        self.size = other.size;
    }

    // TODO: sad slow noises. maybe have a bit field showing which squares have a dude in them. empty is the common case. 
    // TODO: a square can have multiple dudes (NOUN is float). 
    // Unsafe. Must update rulesDirty if mutate through this. Also don't store the pointer.
    pub fn getEntity(self: *Level, pos: Pos) []*Entity {
        var found = std.ArrayList(*Entity).init(TEMP);
        for (self.entities.items) |*e| {
            if (@reduce(.And, e.pos == pos)) {
                found.append(e) catch unreachable;
            }
        }
        return found.items;
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
        std.debug.print("--- LEVEL ---\n", .{});
        std.debug.print("{!s}\n", .{info});
        std.debug.print("--- RULES ---\n", .{});
        inline for (comptime std.enums.values(Noun)) |noun| {
            inline for (comptime std.enums.values(State)) |state| {
                if (self.rules.is(noun, state)) {
                    std.debug.print("{} IS {}\n", .{ noun, state });
                }
            }
        }
        std.debug.print("--- END ---\n", .{});
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
