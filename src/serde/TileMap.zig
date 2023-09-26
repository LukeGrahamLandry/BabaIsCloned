/// This is a direct port of a subset of https://github.com/clickteam-plugin/TileMap 
/// Just enough to load levels from the real game. 
/// The original's license is "Public domain. Do whatever you want with it." 
/// The original uses an old version of https://github.com/richgel999/miniz but zig std has a zlib implementation that conforms to the same RFC. 

const MAGIC = "ACHTUNG!";
const VER_15: u16 = (1 << 8) | 5;

const std = @import("std");
const Err = error.ParseErr;
const logErr = std.log.scoped(.tilemap).debug;

// The slices in the list must use the same allocator as the list or deinit() is unsafe. 
layers: std.ArrayList(Layer),

/// Caller still owns `bytes`, and also the returned value. 
pub fn parse(bytes: []u8, alloc: std.mem.Allocator) !@This() {
    var data: Reader = .{ .data=bytes };

    const magic = std.mem.eql(u8, MAGIC, try data.get_slice(MAGIC.len));
    try require(magic, "Wrong magic.", .{});
    const version = try data.get(u16);
    try require(version == VER_15, "Unknown version {}", .{version});

    var self: @This() = .{ .layers=std.ArrayList(Layer).init(alloc) };
    errdefer self.deinit();

    while (data.data.len > 0) {
        const blockId = try data.get(u32);
        const blockSize = try data.get(u32);
        const expectedRemaining = data.data.len - blockSize;

        switch (blockId) {
            0 => break,
            MAP_ => {
                const propertyCount = try data.get(u16);
                try require(propertyCount == 0, "MAP_ blocks are not supported!", .{});
            },
            LAYR => {
                const layerCount = try data.get(u16);
                try self.layers.ensureTotalCapacity(layerCount);
                for (0..layerCount) |_| {
                    try self.layers.append(try loadLayer(&data, alloc));
                }
            },
            TILE => {
                logErr("TILE blocks are not supported!", .{});
                return Err;
            },
            else => {  // Could skip the unknown block and keep reading (since we know size) but the original doesn't. 
                logErr("Unkown block type {}", .{blockId});
                return Err;  
            }
        }

        try require(expectedRemaining == data.data.len, "Incorrect block size.", .{});
    }

    // self.debugPrint();
    return self;
}

fn loadLayer(data: *Reader, alloc: std.mem.Allocator) !Layer {
    const width = try data.get(u32);
    const height = try data.get(u32);

    // Lots of settings I don't care about. I assume they're for the editor in the engine plugin. 
    // tileWidth, tileHeight, tileset, collision, offsetX, offsetY, scrollX, scrollY, wrapX, wrapY, visible, opacity, sublayerLink
    _ = try data.get_slice(2+2+2+4+4+4+4+1+1+1+4+1+1+1); 

    const dataBlockCount = try data.get(u8);
    try require(dataBlockCount == 2, "Expected dataBlockCount == 2 but got {}.", .{ dataBlockCount });
    try require(try data.get(u32) == MAIN, "First block in LAYR should be MAIN.", .{});

    const mainLayer = try decompressToSlice(Tile, data, width * height, alloc);
    errdefer alloc.free(mainLayer);

    try require(try data.get(u32) == DATA, "Second block in LAYR should be DATA.", .{});
    const cellSize = try data.get(u8);
    try require(cellSize == 1, "Expected cellSize == 1 but found {}", .{ cellSize });
    _ = try data.get(u32);  // defaultValue. I don't care since the compressed data overwrites the whole thing.

    const dataLayer = try decompressToSlice(u8, data, width * height, alloc);
    
    return .{
        .width = width,
        .height = height,
        .main = mainLayer,
        .data = dataLayer,
    };
}

// Reads [compressed len u32][zlib compressed data], decompresses it, checks that it got the right number of entries, and casts it to E. 
fn decompressToSlice(comptime E: type, data: *Reader, count: usize, alloc: std.mem.Allocator) ![]E {
    const expectedSize = count * @sizeOf(E);
    const compressedSize = try data.get(u32);
    const compData = try data.get_slice(@intCast(compressedSize));

    var compStream = std.io.fixedBufferStream(compData);
    var decompStream = try std.compress.zlib.decompressStream(alloc, compStream.reader());
    var decompReader = decompStream.reader();
    const decompData = try decompReader.readAllAlloc(alloc, expectedSize);
    errdefer alloc.free(decompData);
    try require(decompData.len == expectedSize, "Expected {} bytes but got {}", .{ expectedSize, decompData.len });

    var out: [] E = undefined;
    out.len = count;
    out.ptr = @alignCast(@ptrCast(decompData.ptr));
    return out;
}

// TODO: remove. just need this until I figure out how to convert tile numbers into entities. 
fn debugPrint(self: @This()) void {
    for (self.layers.items) |s| {
        for (0..s.height) |h| {
            for ((h*s.width)..(h+1)*s.width) |iii| {
                std.debug.print("[{:05}] ", .{s.main[iii].id});
            }
            std.debug.print("\n", .{});
        }

        for (0..s.height) |h| {
            for ((h*s.width)..(h+1)*s.width) |iii| {
                std.debug.print("({:03}, {:03}) ", .{s.main[iii].pos.x, s.main[iii].pos.y});
            }
            std.debug.print("\n", .{});
        }

        for (0..s.height) |h| {
            for ((h*s.width)..(h+1)*s.width) |ii| {
                std.debug.print("{} ", .{s.data[ii]});
            }
            std.debug.print("\n", .{});
        }
    }
}

pub const Layer = struct {
    width: usize = 0,
    height: usize = 0,
    main: [] Tile = undefined,
    data: [] u8 = undefined,
};

pub const Tile = extern union {
    pub const EMPTY: Tile = .{ .id=0xFFFF }; 
    pos: extern struct {
        x: u8,
        y: u8
    },
    id: u16
};

pub fn deinit(self: @This()) void {
    const alloc = self.layers.allocator;
    for (self.layers.items) |layer| {
        alloc.free(layer.main);
        alloc.free(layer.data);
    }
    self.layers.deinit();
}

const num = std.mem.readIntSliceLittle;
const MAP_ = num(u32, "MAP ");
const TILE = num(u32, "TILE");
const LAYR = num(u32, "LAYR");
const MAIN = num(u32, "MAIN");
const DATA = num(u32, "DATA");

const Reader = struct {
    data: []u8,

    fn get_slice(self: *Reader, count: usize) ![]u8 {
        if (self.data.len >= count) {
            const result = self.data[0..count];
            self.data = self.data[count..];
            return result;
        } else {
            return error.StreamEmpty;
        }
    }

    fn get(self: *Reader, comptime T: type) !T {
        return std.mem.readIntSliceLittle(T, try self.get_slice(@sizeOf(T)));
    }
};

// TODO: consolodate these common parsing helpers. 
fn require(b: bool, comptime msg: []const u8, args: anytype) !void {
    if (!b) {
        logErr(msg, args);
        return Err;
    }
}
