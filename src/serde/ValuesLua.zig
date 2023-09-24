const std = @import("std");
const W = @import("../world.zig");
const logErr = std.log.scoped(.tilemap).debug;
const Err = error.ParseErr;

// TODO: might be more elegant to make this specifically a lua parser and the stuff about the tile set I want is seperate in official.zig 

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
        std.debug.print("Load Obj |{s}|\n", .{ objName.lexeme });

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

        std.debug.print("{}\n", .{ object });
        try tiles.add(object);

        _ = try lexer.expect(.comma, "Expected trailing ','");
    }

    std.debug.print("tileset size = {} bytes\n", .{ @sizeOf(TileSet) });
    return tiles;
}

// TODO: move this to official.zig?
const TileSet = struct {
    const SIZE = 17;
    // TODO: is this bad? limits you to 16x16 and uses space for lots of empty slots
    // TODO: comptime init instead of relying on a zeroed thing? 
    const Data = struct {
        name: []const u8,
        // TODO: replace ^ with block: W.Block,
        id: u16,
    };
    const BitSet = std.bit_set.IntegerBitSet(SIZE * SIZE);

    existingPos: BitSet = BitSet.initEmpty(),
    existingId: BitSet = BitSet.initEmpty(),

    /// tile={x, y} => name="___" id=00n
    posToData: [SIZE * SIZE] Data = std.mem.zeroes([SIZE * SIZE] Data),

    /// id=00n => index in ^
    idToPos: [SIZE * SIZE] u16 = std.mem.zeroes([SIZE * SIZE] u16),

    fn add(self: *TileSet, object: Object) !void {
        const index = (object.y * SIZE) + object.x;
        std.debug.print("index={}\n", .{index});
        try require(!self.existingPos.isSet(index), "Tried to overwrite tile position with {}", .{ object });
        try require(!self.existingId.isSet(object.id), "Tried to overwrite tile id with {}", .{ object });
        self.existingPos.set(index);
        self.existingId.set(object.id);
        self.posToData[index] = .{ .id=object.id, .name=object.name.? };
        self.idToPos[object.id] = index;
    }
};

const Object = struct {
    name: ?[]const u8 = null,
    id: u16,
    x: u8 = 255,
    y: u8 = 255,
};

const TokenType = enum {
    leftBrace,
    rightBrace,
    comma,
    number,
    string,
    identifier,
    equal,
};

const Token = struct {
    lexeme: []const u8,
    ty: TokenType,
};

const Lexer = struct {
    data: []const u8,
    depth: isize = 0,

    // // TODO: remove this. its just for debugging. 
    // fn next(self: *Lexer) !Token {
    //     const token = try self.nextInner();
    //     std.debug.print("[{}]: {s}\n", .{ token.ty, token.lexeme });
    //     return token;
    // }

    fn next(self: *Lexer) !Token {
        try self.skipWhitespace();
        switch (try self.peek()) {
            '"' => {
                self.advance();  // "
                const start = self.data;
                // TODO: do I need to support \" escape sequence? 
                var len: usize = 0;
                while (try self.pop() != '"') {
                    len += 1;
                }

                return .{ .ty = .string, .lexeme = start[0..len] };
            },
            '}' => {
                self.depth -= 1;
                return try self.single(.rightBrace);
            },
            '{' => {
                self.depth += 1;
                return try self.single(.leftBrace);
            },
            ',' => return try self.single(.comma),
            '=' => return try self.single(.equal),
            '-', '0'...'9' => {
                const start = self.data;
                self.advance();
                var len: usize = 1;
                while (true) {
                    switch (try self.peek()) {
                        '0'...'9' => {
                            len += 1;
                            self.advance();
                        },
                        else => break,
                    }
                }
                return .{ .ty=.number, .lexeme=start[0..len] };
            },
            else => {
                const start = self.data;
                var len: usize = 0;
                while (true) {
                    const c = try self.peek();
                    if (std.ascii.isWhitespace(c)){
                        break;
                    }
                    switch (c) {
                        '{', '}', ',', '=' => {
                            break;
                        },
                        else => {}
                    }
                    self.advance();
                    len += 1;
                }
                return .{ .ty = .identifier, .lexeme = start[0..len] };
            }
        }
    }

    /// Consumes until the closing `}` of the current object. Nested objects are supported (ie. additional `{` found inside consume thier `}` first).  
    /// For example, after reading an opening `{`, calling this could consume `0, 1, { "a", "b" }, c = 2 } }`
    /// Does not consume a trailing comma at the end of the current object. 
    /// Returns an error if the src runs out of bytes before the object is closed. 
    fn skipCurrentObject(self: *Lexer) !void {
        const targetDepth = self.depth - 1;
        while (self.depth > targetDepth) {
            _ = try self.next();
        }
    }

    /// Consumes until a `,` (ignoring any inside a new object). 
    /// For example, after reading `name =`, calling this could consume `{ 0, 1 },` 
    fn skipCurrentValue(self: *Lexer) !void {
        while (true) {
            const token = try self.next();
            switch (token.ty) {
                .comma => break,
                .leftBrace => try self.skipCurrentObject(),
                else => {},
            }
        }
    }

    fn single(self: *Lexer, ty: TokenType) !Token {
        const l = self.data[0..1];
        self.advance();
        return .{ .ty=ty, .lexeme=l };
    }

    fn skipWhitespace(self: *Lexer) !void {
        while (true) {
            if (self.data.len == 0){
                break;
            }

            if (std.ascii.isWhitespace(try self.peek())) {
                self.advance();
            } else if (try self.peek() == '-') {
                if (self.data.len > 1 and self.data[1] == '-') {
                    self.advance();
                    self.advance();
                    while (try self.pop() != '\n') {}  // TODO: are there other line breaks? 
                } else {
                    break;
                }
            } else {
                break;
            }
        }
    }

    fn expect(self: *Lexer, ty: TokenType, comptime msg: []const u8) ![]const u8 {
        const token = try self.next();
        try require(token.ty == ty, msg, .{});
        return token.lexeme;
    }

    // Doesn't bounds check so only call if you've already peeked. 
    fn advance(self: *Lexer) void {
        _ = self.pop() catch unreachable;
    }

    fn pop(self: *Lexer) !u8 {
        const b = try self.peek();
        self.data = self.data[1..];
        return b;
    }

    fn peek(self: *Lexer) !u8 {
        if (self.data.len == 0) {
            logErr("EOF\n", .{});
            return Err;
        }
        return self.data[0];
    }
};

fn require(b: bool, comptime msg: []const u8, args: anytype) !void {
    if (!b) {
        logErr(msg, args);
        return Err;
    }
}
