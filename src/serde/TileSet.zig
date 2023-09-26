const std = @import("std");
const W = @import("../world.zig");
const logErr = std.log.scoped(.tilemap).debug;
const Err = error.ParseErr;

const Lexer = @import("LuaLexer.zig");
const TileSet = @This();

pub fn parse(bytes: []const u8) !TileSet {
    var tiles: TileSet = .{};

    const HEADER = "tileslist =";
    const startIndex = std.mem.indexOf(u8, bytes, HEADER) orelse {
        logErr("var tileslist not found.", .{});
        return Err;
    };

    const beginAt = startIndex + HEADER.len;
    var lexer: Lexer = .{ .data=bytes[beginAt..] };
    
    _ = try lexer.expect(.leftBrace, "Expected data start.");

    while (true) {
        const objName = try lexer.next();
        if (objName.ty == .rightBrace) {
            break;
        }

        try require(objName.ty == .identifier, "Expected field name.", .{});

        _ = try lexer.expect(.equal, "Expected '=' after identifier.");
        _ = try lexer.expect(.leftBrace, "Expected '{{' to start object.");

        const PREFIX = "object";
        if (!std.mem.startsWith(u8, objName.lexeme, PREFIX)) {
            try lexer.skipCurrentObject();
            _ = try lexer.expect(.comma, "Expected trailing ','");
            continue;
        }


        const id = try std.fmt.parseInt(u16, objName.lexeme[PREFIX.len..], 10);
        var object: Object = .{ .id=id };

        // Now read inner values
        // TODO: maybe split this out into an ObjectIter or something. It's annoyingly similar to the outer level. 
        while (true) {
            const fieldName = try lexer.next();
            if (fieldName.ty == .rightBrace) {
                break;
            }

            try require(fieldName.ty == .identifier, "Expected field name.", .{});
            _ = try lexer.expect(.equal, "Expected '=' after identifier.");

            if (std.mem.eql(u8, fieldName.lexeme, "name")) {
                object.name = try lexer.expect(.string, "Expected name to be string");
                _ = try lexer.expect(.comma, "Expected ',' after field.");
            } else if (std.mem.eql(u8, fieldName.lexeme, "layer")) {
                const layerStr = try lexer.expect(.number, "Expected layer to be number");
                object.layer = try std.fmt.parseInt(u8, layerStr, 10);
                _ = try lexer.expect(.comma, "Expected ',' after field.");
            } else if (std.mem.eql(u8, fieldName.lexeme, "tile")) {
                const MSG = "Expected 'tile' of type object.";
                _ = try lexer.expect(.leftBrace, MSG);
                const xStr = try lexer.expect(.number, MSG);
                _ = try lexer.expect(.comma, MSG);
                const yStr = try lexer.expect(.number, MSG);
                _ = try lexer.expect(.rightBrace, MSG);
                _ = try lexer.expect(.comma, MSG);
                object.x = try std.fmt.parseInt(u8, xStr, 10);
                object.y = try std.fmt.parseInt(u8, yStr, 10);
            } else {
                try lexer.skipCurrentValue();
            }
        }

        // Could save a more compact version of this somewhere. Or include it in the binary but that feels icky. 
        // std.debug.print("{} {s} {} {}\n", .{ object.id, object.name.?, object.x, object.y });
        try tiles.add(object);

        _ = try lexer.expect(.comma, "Expected trailing ','");
    }

    logErr("tileset size = {} bytes\n", .{ @sizeOf(TileSet) });
    return tiles;
}

const strToBlock = @import("official.zig").strToBlock;

// TODO: tile (0, 0) is magic edge block. Or just make the levels one smaller in every dimension since I'm doing bounds checks anyway. 
const SIZE = 17;
const Data = struct {
    block: W.Block,
    // TODO: replace ^ with block: W.Block. then this would have no dynamic memory which is nice
    id: u16,
    layer: u8
};

const BitSet = std.bit_set.IntegerBitSet(SIZE * SIZE);
existingPos: BitSet = BitSet.initEmpty(),
existingId: BitSet = BitSet.initEmpty(),

// TODO: is this bad? limits you to 16x16 and uses space for lots of empty slots

/// tile={x, y} => name="___" id=00n
posToData: [SIZE * SIZE] Data = undefined,
/// id=00n => index in ^
idToPos: [SIZE * SIZE] u16 = undefined,

// TODO: what happens when they want two of the same block type but on different layers? do they?
blockToLayer: BlockMap(u8) = .{},

// TODO: remove once I can parse all. this sucks. just cause I don't want to change the test rn. 
attempts: usize = 0, 


fn add(self: *TileSet, object: Object) !void {
    const index = (object.y * SIZE) + object.x;

    try require(index < self.idToPos.len, "Object index ({} {}) => {} is too high.", .{ object.x, object.y, index });
    try require(object.id < self.posToData.len, "Object id {} is too high.", .{ object.id });
    try require(!self.existingPos.isSet(index), "Tried to overwrite tile position with {}", .{ object });
    try require(!self.existingId.isSet(object.id), "Tried to overwrite tile id with {}", .{ object });
    self.attempts += 1;

    // TODO: don't allow loading the same type of block twice? 
    const block = strToBlock(object.name.?) orelse {
        logErr("Failed to parse block type '{s}'", .{ object.name.? });
        // TODO: this should be a hard error once I can parse everything. 
        return;
    };

    self.existingPos.set(index);
    self.existingId.set(object.id);
    self.posToData[index] = .{ .id=object.id, .block=block, .layer=object.layer };
    self.idToPos[object.id] = index;
    if (self.blockToLayer.contains(block)) {
        logErr("Repeated block type {}", .{ block });
    }
    self.blockToLayer.put(block, object.layer);
}

pub fn getBlock(self: TileSet, x: usize, y: usize) ?W.Block {
    const empty = x == 255 and y == 255;
    const edge = x == 0 and y == 0;
    if (empty or edge) {
        return null;
    }
    const index = (y * SIZE) + x;
    if (index >= self.existingPos.capacity() or !self.existingPos.isSet(index)) {
        return null;
    }
    return self.posToData[index].block;
}


fn BlockMap(comptime V: type) type {
    // TODO: clever comptime introspection instead of hard-coding it. 
    return struct {
        noun: std.EnumMap(W.Noun, V) = .{},
        object: std.EnumMap(W.Noun, V) = .{},
        state: std.EnumMap(W.State, V) = .{},
        connect: std.EnumMap(W.Connect, V) = .{},

        pub fn put(self: *@This(), key: W.Block, value: V) void {
            switch (key) {
                .Noun => |word| self.noun.put(word, value),
                .Object => |word| self.object.put(word, value),
                .State => |word| self.state.put(word, value),
                .Connect => |word| self.connect.put(word, value),
            }
        }

        pub fn get(self: *@This(), key: W.Block) ?V {
            return switch (key) {
                .Noun => |word| self.noun.get(word),
                .Object => |word| self.object.get(word),
                .State => |word| self.state.get(word),
                .Connect => |word| self.connect.get(word),
            };
        }

        pub fn contains(self: *@This(), key: W.Block) bool {
            return switch (key) {
                .Noun => |word| self.noun.contains(word),
                .Object => |word| self.object.contains(word),
                .State => |word| self.state.contains(word),
                .Connect => |word| self.connect.contains(word),
            };
        }
    };
}

const Object = struct {
    name: ?[]const u8 = null,
    id: u16,
    x: u8 = 255,
    y: u8 = 255,
    layer: u8 = 20  // TODO: use this when rendering 
};

fn require(b: bool, comptime msg: []const u8, args: anytype) !void {
    if (!b) {
        logErr(msg, args);
        return Err;
    }
}

// TODO: ignore this test if real game not installed. 
test "don't choke on values.lua" {
    // TODO: don't hardcode my path. need a shared function that cleverly finds it based on your operating system. 
    const valueslua = "/Users/luke/Library/Application Support/Steam/steamapps/common/Baba Is You/Baba Is You.app/Contents/Resources/Data/values.lua";
    const data = try @import("official.zig").readAlloc(valueslua, W.TEMP);
    const tiles = try parse(data);

    try std.testing.expectEqual(tiles.attempts, 156);
    try std.testing.expectEqual(tiles.attempts, 156);
}
