/// The levels have a text file (.ld) that looks like dump of some crazy hash map thing. 
/// But they don't seem to have enough information load the level. 
/// They all have an assosiated binary file (.l) I can't read that starts with the magic 'ACHTUNG!'.
/// I know the game engine they use is Multimedia Fusion 2 so googling for that + tile map, 
/// eventually found https://github.com/clickteam-plugin/TileMap which uses the same magic number!
/// Recreating the parsing code and now I get numbers in the same shape as the objects in the level!
/// And the numbers seem consistant, walls are always 257. Next question is where do these numbers come from? 
/// As bytes they're like tileset positions the word baba is (9, 1) and searching for that,
/// values.lua has object020 = { name=text_baba, tile={ 9, 1 } }. So I also need to parse lua I guess? 
/// I think the .ld files are diffs agains that structure from values.lua. 
/// Then every LAYR there's a DATA block of a bunch of 3s. Those are direction! Using the level editor to place dudes can get 0-3 there. 
/// The editor lets you put overlapping dudes on different layers, and they just show up as a new LAYR block in the tilemap. 

const std = @import("std");
const W = @import("../world.zig");
const TileMap = @import("TileMap.zig");
const ValuesLua = @import("ValuesLua.zig");

const ParseErr = error.LevelParseFailed;

// TODO: something that loops over the data files and loads all levels. 

pub fn loadLevel(alloc: std.mem.Allocator) !W.Level {
    {
        const valueslua = "/Users/luke/Library/Application Support/Steam/steamapps/common/Baba Is You/Baba Is You.app/Contents/Resources/Data/values.lua";
        const file = try std.fs.openFileAbsolute(valueslua, .{});
        defer file.close();
        const data = try file.reader().readAllAlloc(W.TEMP, std.math.maxInt(u16));
        const values = try ValuesLua.parse(data);
        _ = values;
    }
    
    
    
    // const template = "/Users/luke/Library/Application Support/Steam/steamapps/common/Baba Is You/Baba Is You.app/Contents/Resources/Data/Worlds/baba/{}level.l";
    // for (0..1) |i| {  // 340
    //     std.debug.print("START {}\n", .{i});
    //     var buf: [512] u8 = undefined;
    //     const path = try std.fmt.bufPrint(&buf, template, .{ i });
    //     const file = std.fs.openFileAbsolute(path, .{}) catch continue;
    //     defer file.close();
    //     const data = try file.reader().readAllAlloc(W.TEMP, std.math.maxInt(u16));
        
    //     const tiles = TileMap.parse(data, W.TEM) catch {
    //         std.debug.print("FAIL {}\n", .{i});
    //         continue;
    //     };
    //     std.mem.doNotOptimizeAway(tiles);
    // }
    // const path = "/Users/luke/Library/Application Support/Steam/steamapps/common/Baba Is You/Baba Is You.app/Contents/Resources/Data/Worlds/levels/15level.l";
    // const file = try std.fs.openFileAbsolute(path, .{});
    // defer file.close();
    // const data = try file.reader().readAllAlloc(W.TEMP, std.math.maxInt(u16));
    // _ = try TileMap.parse(data, W.TEM);
    

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
