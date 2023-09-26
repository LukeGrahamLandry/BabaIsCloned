/// A lexer for a tiny subset of Lua (just simple table initilization). 
/// Enough to read values.lua to extract the base tileset info. 

const std = @import("std");
const W = @import("../world.zig");
const require = @import("official.zig").require;
const Lexer = @This();

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


data: []const u8,
depth: isize = 0,

pub fn next(self: *Lexer) !Token {
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
pub fn skipCurrentObject(self: *Lexer) !void {
    const targetDepth = self.depth - 1;
    while (self.depth > targetDepth) {
        _ = try self.next();
    }
}

/// Consumes until a `,` (ignoring any inside a new object). 
/// For example, after reading `name =`, calling this could consume `{ 0, 1 },` 
pub fn skipCurrentValue(self: *Lexer) !void {
    while (true) {
        const token = try self.next();
        switch (token.ty) {
            .comma => break,
            .leftBrace => try self.skipCurrentObject(),
            else => {},
        }
    }
}

pub fn expect(self: *Lexer, ty: TokenType, comptime msg: []const u8) ![]const u8 {
    const token = try self.next();
    try require(token.ty == ty, msg, .{});
    return token.lexeme;
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
    try require(self.data.len > 0, "EOF", .{});
    return self.data[0];
}

test "lex lua" {
    const src = "{ a = { \n\n\n b = { 1,0},c = -10, \n --|this is a comment \" }}}{{{| \n d = \"e\"}, }";
    const tokens = &[_] TokenType { .leftBrace, .identifier, .equal, .leftBrace, .identifier, .equal, .leftBrace, .number, .comma, .number, .rightBrace, .comma, .identifier, .equal, .number, .comma, .identifier, .equal, .string, .rightBrace, .comma, .rightBrace };
    var lexer: Lexer = .{ .data=src };
    for (tokens) |expected| {
        try std.testing.expectEqual(expected, (try lexer.next()).ty);
    }

    try std.testing.expect(std.meta.isError(lexer.next()));
    try std.testing.expectEqual(lexer.depth, 0);
}
