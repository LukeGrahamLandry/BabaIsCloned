const std = @import("std");
const assert = std.debug.assert;
pub const Pos = @Vector(2, i32);

// TODO: could I have a debug version that doesn't reuse memory and zeros old stuff to detect use after the frame ends? 
// This gets reset every frame, so you don't have to free stuff manually. None of this is thread safe!
pub var frameArena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
pub var TEMP = frameArena.allocator();

pub const Level = struct {
    entities: std.ArrayList(Entity),
    actionHistory: std.ArrayList(Input),  // TODO: include in save file. 
    rules: Rules,
    size: Pos,
    rulesDirty: bool = false,
    somethingChanged: bool = false,
    state: GameState = .None,
    pub fn init(alloc: std.mem.Allocator, size: Pos) Level {
        return .{
            .entities = std.ArrayList(Entity).init(alloc),
            .actionHistory = std.ArrayList(Input).init(alloc),
            .rules = Rules.init(),
            .size = size,
        };
    }

    pub fn handleInput(self: *Level, in: Input) !void {
        self.somethingChanged = false;
        switch (in) {
            .Left => self.movePlayer(Dir.LEFT),
            .Right => self.movePlayer(Dir.RIGHT),
            .Up => self.movePlayer(Dir.UP),
            .Down => self.movePlayer(Dir.DOWN),
            .Wait => {},
        }
        self.tick();

        assert(!self.rulesDirty or self.somethingChanged); // rules need update, something must have changed. 
        if (self.somethingChanged) {
            self.checkDefeat();
            try self.actionHistory.append(in);

            if (self.levelWon()) {
                self.state = .Win;
            } else if (self.nobodyIsYou()) {
                self.state = .Lose;
            }
        }
    }
    
    fn checkDefeat(self: *Level) void {
        if (!self.rules.exists(.Defeat) or !self.rules.exists(.You)) {
            return;
        }

        var i = self.entities.items.len - 1;
        while (i > 0) {
            i -= 1;
            const e = self.entities.items[i];
            switch (e.block) {
                .Object => |noun| {
                    if (self.rules.is(noun, .You)) {
                        if (self.posContains(e.pos, .Defeat)) {
                            _ = self.entities.swapRemove(i);
                            self.somethingChanged = true;
                        }
                    }
                },
                else => {}
            }
        }   
    }
    
    pub fn levelWon(self: *Level) bool {
        for (self.allOfState(.Win)) |win| {
            if (self.posContains(win.pos, .You)) {
                return true;
            }
        }

        return false;
    }

    pub fn nobodyIsYou(self: *Level) bool {
        return self.allOfState(.You).len == 0;
    }

    fn posContains(self: *Level, pos: Pos, state: State) bool {
        if (!self.rules.exists(state)) {
            return false;  // No rule causes the state so won't find anything. 
        }

        for (self.getEntity(pos)) |check| {
            switch (check.block) {
                .Object => |noun| {
                    if (self.rules.is(noun, state)) {
                        return true;
                    }
                },
                else => {}
            }
        }
        return false;
    }

    pub fn tick(self: *Level) void {
        if (self.rulesDirty) {
            self.updateRules();
            self.rulesDirty = false;
            self.rules.debugPrint();
        }
        // TODO: X is MOVE
        // TODO: this gets called when you move or wait
    }

    pub fn movePlayer(self: *Level, dir: Pos) void {
        if (!self.rules.exists(.You)) {
            return;
        }

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
        self.somethingChanged = true;
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
                .Connect => |word| {
                    switch (word) {
                        .Is => {
                             self.updateFromIs(e.pos, Dir.UP);
                    self.updateFromIs(e.pos, Dir.LEFT);
                        },
                        else => {},
                    }
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
                        self.somethingChanged = true;
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
        self.state = other.state;
        self.somethingChanged = other.somethingChanged;
    }

    // TODO: sad slow noises. maybe have a bit field showing which squares have a dude in them. empty is the common case. 
    // Unsafe. Must update rulesDirty if mutate through this. 
    // This has a scary lifetime! Pointers are invalidated if the list is modified. The slice is in temp alloc so invalid at end of frame. 
    pub fn getEntity(self: *Level, pos: Pos) []*Entity {
        var found = std.ArrayList(*Entity).init(TEMP);
        for (self.entities.items) |*e| {
            if (@reduce(.And, e.pos == pos)) {
                found.append(e) catch unreachable;
            }
        }
        return found.items;
    }

    // TODO: anything that switches to select object must actually accept text as well because text can be states. 
    pub fn allOfState(self: *Level, state: State) []*Entity {
        if (!self.rules.exists(state)){
            return &[_]*Entity{};  // No rule causes the state so won't find anything. 
        }

        var found = std.ArrayList(*Entity).init(TEMP);
        for (self.entities.items) |*e| {
            switch (e.block) {
                .Object => |noun| {
                    if (self.rules.is(noun, state)) {
                        found.append(e) catch @panic("OOM");
                    }
                },
                else => {}
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
        const info = @import("serde/save.zig").saveLevel(self, TEMP);
        std.debug.print("--- LEVEL ---\n", .{});
        std.debug.print("{!s}\n", .{info});
        self.rules.debugPrint();
        std.debug.print("--- END ---\n", .{});
    }
};

pub const Rules = struct {
    states: std.EnumMap(Noun, std.EnumSet(State)) = .{}, 
    activeStates: std.EnumSet(State) = .{},

    pub fn is(self: Rules, noun: Noun, state: State) bool {
        return self.states.get(noun).?.contains(state);
    }

    pub fn set(self: *Rules, noun: Noun, state: State) void {
        self.states.getPtr(noun).?.insert(state);
        self.activeStates.insert(state);
    }

    // Lets you know if any nouns are that state so you can avoid expensive handling for states that aren't even in the level. 
    pub fn exists(self: Rules, state: State) bool {
        return self.activeStates.contains(state);
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
        self.activeStates = std.EnumSet(State).initEmpty();
        self.activeStates.insert(.Push);  // Text is always push. 
    }

    pub fn init() Rules {
        var self: Rules = .{};
        self.clear();
        return self;
    }

    pub fn debugPrint(self: Rules) void {
        std.debug.print("--- RULES ---\n", .{});
        inline for (comptime std.enums.values(Noun)) |noun| {
            inline for (comptime std.enums.values(State)) |state| {
                if (self.is(noun, state)) {
                    std.debug.print("{} IS {}\n", .{ noun, state });
                }
            }
        }
    }
};

pub const Input = enum {
    // TODO: split directions into something I can reuse? 
    Left,
    Right,
    Up,
    Down,
    Wait
};

pub const Entity = struct {
    block: Block,
    pos: Pos,
    // TODO: direction. 
};

pub const Block = union(BlockType) {
    Noun: Noun,
    State: State,
    Object: Noun,
    Connect: Connect,

    pub fn isText(self: Block) bool {
        return self != @field(Block, "Object");
    }


    pub fn name(self: Block) []const u8 {
        return switch (self) {
            .Noun => |noun| @tagName(noun),
            .Object => |noun| @tagName(noun),
            .State => |state| @tagName(state),
            .Connect => |word| @tagName(word),
        };
    }
};

pub const BlockType = enum {
    Noun,
    State,
    Object,
    Connect,
};

// TODO: maybe its a little silly for these to be a compile time concept. 
pub const Noun = enum {
    Baba,
    Rock,
    Wall,
    Flag,
    Skull,
    Water,

    // TODO: I need layered rendering so this doesnt suck
    // Background things
    Tile,
    Grass,
};

pub const State = enum {
    You,
    Push,
    Stop,
    Win,
    Defeat,
};

pub const Connect = enum {
    Is,
    And,
};

// TODO: make this an enum so I can reuse for entity direction. 
pub const Dir = struct {
    pub const UP: Pos = .{ 0, -1 };
    pub const DOWN: Pos = .{ 0, 1 };
    pub const LEFT: Pos = .{ -1, 0 };
    pub const RIGHT: Pos = .{ 1, 0 };
};

pub const GameState = enum {
    None,
    Win,
    Lose
};
