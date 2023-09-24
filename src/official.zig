/// The levels have a text file (.ld) that looks like dump of some crazy hash map thing. 
/// But they don't seem to have enough information load the level. 
/// They all have an assosiated binary file (.l) I can't read that starts with the magic 'ACHTUNG!'.
/// I know the game engine they use is Multimedia Fusion 2 so googling for that + tile map, 
/// eventually found https://github.com/clickteam-plugin/TileMap which uses the same magic number!
/// Recreating the parsing code and now I get numbers in the same shape as the objects in the level!

const std = @import("std");
const W = @import("world.zig");
const TileMap = @import("TileMap.zig");

const ParseErr = error.LevelParseFailed;

pub fn loadLevel(alloc: std.mem.Allocator) !W.Level {
    const path = "/Users/luke/Library/Application Support/Steam/steamapps/common/Baba Is You/Baba Is You.app/Contents/Resources/Data/Worlds/baba/0level.l";
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    const data = try file.reader().readAllAlloc(W.TEMP, std.math.maxInt(u16));

    const tiles = try TileMap.parse(data, std.heap.c_allocator);
    std.debug.print("{}\n", .{ tiles });

    var self = W.Level.init(alloc, .{10, 10});
    self.updateRules();
    return self;
}

fn strToBlock(str: []const u8) ?W.Block {
    var parts = std.mem.splitScalar(u8, str, '_');
    const first = parts.next().?;
    if (parts.next()) |second| {
        if (!std.mem.eql(u8, first, "text")) {
            return null;
        }

        if (find(W.State, second)) |state| {
            return .{ .State = state };
        }

        if (find(W.Noun, second)) |noun| {
            return .{ .Noun = noun };
        }

        if (std.mem.eql(u8, second, "is")) {
            return .Is;
        }
        
        if (std.mem.eql(u8, second, "and")) {
            return .And;
        }

    } else {
        if (find(W.Noun, first)) |noun| {
            return .{ .Object = noun };
        }
    }

    return null;
}

fn find(comptime E: type, str: []const u8) ?E {
    for (std.enums.values(E)) |value| {
        const name = @tagName(value);
        if (name.len != str.len) {
            continue;
        }

        for (0..name.len) |i| {
            if (std.ascii.toLower(name[i]) != str[i]) {
                break;
            }
        } else {
            return value;
        }

    }

    return null;
}
