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
/// For using thier textures, the images are grayscale and values.lua has a 'color' field for each entity, 
/// but its just two numbers like another tile position. .ld gives a pallete for the level! that's a png tile map of colours.

const std = @import("std");
const W = @import("../world.zig");
pub const TileMap = @import("TileMap.zig");
pub const TileSet = @import("TileSet.zig");

// TODO: something that loops over the data files and loads all levels. 

pub fn readAlloc(absPath: []const u8, alloc: std.mem.Allocator) ![]u8 {
    const file = try std.fs.openFileAbsolute(absPath, .{});
    defer file.close();
    return try file.reader().readAllAlloc(alloc, std.math.maxInt(u32));
}

pub var tileSet: ?TileSet = null;

// TODO: seperate doing the work from accessing the file system. 
pub fn loadLevel(alloc: std.mem.Allocator, tileMapPath: []const u8) !W.Level {
    const valuesPath = "/Users/luke/Library/Application Support/Steam/steamapps/common/Baba Is You/Baba Is You.app/Contents/Resources/Data/values.lua";
    // TODO: i want to use temp alloc but the TileSet keeps the little strings for sprite paths. 
    //       so now it keeps the whole code alive. 
    const valuesData = try readAlloc(valuesPath, alloc);  
    if (tileSet == null) {
        tileSet = try TileSet.parse(valuesData);
    }
    
    const data = try readAlloc(tileMapPath, W.TEMP);
    const tilemap = try TileMap.parse(data, W.TEMP);

    // TODO: include the other layers (the dudes that are overlaping). 
    //       I think that's not a gameplay thing, they just force it into their existing tile format. 
    const width = @as(i32, @intCast(tilemap.layers.items[0].width));
    const height = @as(i32, @intCast(tilemap.layers.items[0].height));
    var self = W.Level.init(alloc, .{ width, height });

    for (0..@intCast(height)) |y| {
        for (0..@intCast(width)) |x| {
            const index = (y * @as(usize, @intCast(width))) + x;
            const pos = tilemap.layers.items[0].main[index].pos;
            if (tileSet.?.getBlock(pos.x, pos.y)) |block|{
                try self.addEntity(.{ @as(i32, @intCast(x)), @as(i32, @intCast(y)) }, block);
            }
        }
    }
    
    // const template = "/Users/luke/Library/Application Support/Steam/steamapps/common/Baba Is You/Baba Is You.app/Contents/Resources/Data/Worlds/baba/{}level.l";
    // for (0..1) |i| {  // 340
    //     std.debug.print("START {}\n", .{i});
    //     var buf: [512] u8 = undefined;
    //     const path = try std.fmt.bufPrint(&buf, template, .{ i });
    //     const data = try readAlloc(path, W.TEMP);
        
    //     const tiles = TileMap.parse(data, W.TEM) catch {
    //         std.debug.print("FAIL {}\n", .{i});
    //         continue;
    //     };
    //     std.mem.doNotOptimizeAway(tiles);
    // }


    

    self.updateRules();
    return self;
}

pub fn strToBlock(str: []const u8) ?W.Block {
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

        if (find(W.Connect, second)) |word| {
            return .{ .Connect = word };
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

const Err = error.LevelParseFailed;
pub const logErr = std.log.scoped(.baba).debug;
pub fn require(b: bool, comptime msg: []const u8, args: anytype) !void {
    if (!b) {
        logErr(msg, args);
        return Err;
    }
}
