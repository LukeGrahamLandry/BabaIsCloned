/// This is a direct port from https://github.com/clickteam-plugin/TileMap 
/// Just enough to load levels from the real game. 
/// The original's license is "Public domain. Do whatever you want with it." 

const MAGIC = "ACHTUNG!";
const VER_15: u16 = (1 << 8) | 5;

const std = @import("std");
const Err = error.ParseErr;
const logErr = std.log.scoped(.tilemap).debug;

// TODO: use std.compress.zlib.decompressStream (they should both implement the same RFC)
extern fn mz_uncompress(pDest: *anyopaque, pDest_len: *u64, pSource: *const anyopaque, source_len: u64) i32;

layers: std.ArrayList(Layers),

pub fn parse(bytes: []u8, alloc: std.mem.Allocator) !@This() {
    var data: Reader = .{ .data=bytes };
    if (!std.mem.eql(u8, MAGIC, try data.get_slice(MAGIC.len))){
        logErr("Wrong magic.", .{});
        return Err;
    }

    if (try data.get(u16) != VER_15) {
        logErr("Unknown version", .{});
        return Err;
    }

    var self: @This() = .{ .layers=std.ArrayList(Layers).init(alloc) };

    while (data.data.len > 0) {
        const blockId = try data.get(u32);
        const blockSize = try data.get(u32);
        // TODO: assert that block was the right size at the end of parsing. 
        switch (blockId) {
            0 => break,
            MAP_ => {
                logErr("Map block.", .{});
                const propertyCount = try data.get(u16);
                if (propertyCount != 0) {  // TODO: see if they ever use this. 
                    logErr("MAP_ blocks are not supported!", .{});
                    return Err;
                }
                // Expect blockSize == 2 because it's just the count. 
            },
            LAYR => {
                logErr("Layer block. blockSize:{}", .{blockSize});
                const layerCount = try data.get(u16);
                logErr("layerCount:{}", .{layerCount});
                try self.layers.ensureTotalCapacity(layerCount);
                for (0..layerCount) |i| {
                    try self.layers.append(try loadLayer(&data, alloc));
                    _ = i;
                    
                }
            },
            TILE => {
                logErr("TILE blocks are not supported!", .{});
                return Err;
            },
            else => {
                if (data.data.len == 0) {
                    break;  // TODO: Does this happen?
                } else {
                    logErr("Unkown block type {}", .{blockId});
                    // Could skip the unknown block and keep reading (since we know size) but the original doesn't. 
                    return Err;  
                }
            }
        }
    }

    return self;
}

fn loadLayer(data: *Reader, alloc: std.mem.Allocator) !Layers {
    var theLayers: Layers = .{};
    const width = try data.get(u32);
    const height = try data.get(u32);
    logErr("w:{} h:{}", .{ width, height });

    _ = try data.get_slice(4); // tileWidth, tileHeight 
    _ = try data.get_slice(2); // tileset, collision 
    _ = try data.get_slice(16); // offsetX, offsetY, scrollX, scrollY
    _ = try data.get_slice(7);  // wrapX, wrapY, visible, opacity
    _ = try data.get_slice(3);  // sublayerLink

    const dataBlockCount = try data.get(u8);
    logErr("dataBlockCount:{}", .{dataBlockCount});
    if (dataBlockCount != 2) {
        logErr("dataBlockCount != 2... this doesn't look good.", .{});
        // TODO: return Err; 
    }

    for (0..dataBlockCount) |i| {
        const blockId = try data.get(u32);
        switch (blockId) {
            MAIN => {
                if (theLayers.main != null) {
                    logErr("Expected only one main block per layer. ", .{});
                    return Err;
                }
                
                var layer = Layer(Tile).init(alloc, Tile.EMPTY);

                logErr("layer, main", .{});
                try layer.resize(width, height);

                var realSize = layer.byteSize();
                const dataPtr = layer.tiles.items.ptr;
                const compressedSize = try data.get(u32);
                const compressedData = try data.get_slice(@intCast(compressedSize));
                
                const status = mz_uncompress(dataPtr, &realSize, compressedData.ptr, compressedSize);
                if (status != 0) {
                    logErr("Failed to decompress ({})", .{ status });
                    return Err;
                }
                if (realSize != layer.byteSize()) {
                    logErr("hmmm... expected {} bytes but got {}", .{ layer.byteSize(), realSize });
                    return Err;
                }

                // TOD: remove and replace ^ 
                // Make sure that zig's zlib is the same as the other one. 
                var reader = std.io.fixedBufferStream(compressedData);
                var otherDecompressed = try std.compress.zlib.decompressStream(alloc, reader.reader());
                var againReader = otherDecompressed.reader();
                const dataAgain = try againReader.readAllAlloc(alloc, 999999999);
                defer alloc.free(dataAgain);
                std.debug.assert(dataAgain.len == layer.tiles.items.len*2);
                var ii: usize = 0;
                while ((ii + 1) < dataAgain.len) {
                    std.debug.assert(dataAgain[ii] == layer.tiles.items[ii / 2].pos.x);
                    std.debug.assert(dataAgain[ii + 1] == layer.tiles.items[ii / 2].pos.y);
                    ii += 2;
                }
                theLayers.main = layer;

                for (0..height) |h| {
                    for ((h*width)..(h+1)*width) |iii| {
                        std.debug.print("{:05} ", .{layer.tiles.items[iii].id});
                    }
                    std.debug.print("\n", .{});
                }

                for (0..height) |h| {
                    for ((h*width)..(h+1)*width) |iii| {
                        std.debug.print("({:03}, {:03}) ", .{layer.tiles.items[iii].pos.x, layer.tiles.items[iii].pos.y});
                    }
                    std.debug.print("\n", .{});
                }
            },
            DATA => {
                if (theLayers.data != null) {
                    logErr("Expected only one data block per layer. ", .{});
                    return Err;
                }
                logErr("layer, data", .{});
                const cellSize = try data.get(u8);
                const defaultValue = try data.get(u32);
                const compressedSize = try data.get(u32);
                const compressedData = try data.get_slice(@intCast(compressedSize));

                if (cellSize != 1) {
                    logErr("cellSize != 1 in layer data block.", .{});
                    return Err;
                }

                // TODO: defaultValue does nothing because the whole compressed thing overwrites it anyway? 
                if (defaultValue > std.math.maxInt(u8)){
                    logErr("defaultValue = {} > 255", .{ defaultValue });
                }

                var layer = Layer(u8).init(alloc, @intCast(defaultValue));
                _ = layer;
                logErr("cellSize:{} compressedSize:{} defaultValue:{}", .{cellSize, compressedSize, defaultValue});

                var reader = std.io.fixedBufferStream(compressedData);
                var otherDecompressed = try std.compress.zlib.decompressStream(alloc, reader.reader());
                var againReader = otherDecompressed.reader();
                const dataAgain = try againReader.readAllAlloc(alloc, 999999999);
                defer alloc.free(dataAgain);

                // TODO: just pass this as the maxsize to readAllAlloc
                const layerBytesSize = width * height;
                if (dataAgain.len != layerBytesSize) {
                    logErr("hmmm... expected {} bytes but got {}", .{ layerBytesSize, dataAgain.len });
                    return Err;
                }

                for (0..height) |h| {
                    for ((h*height)..(h+1)*height) |ii| {
                        std.debug.print("{} ", .{dataAgain[ii]});
                    }
                    std.debug.print("\n", .{});
                }

                
            },
            else => {
                logErr("Unkown layer block type {}", .{blockId});
                return Err;  // TODO: do i need to just read zero and continue looping here? 
            }
        }
        _ = i;
        
    }

    return theLayers;
}

pub const Layers = struct {
    main: ?Layer(Tile) = null,
    data: ?Layer(u8) = null
};

fn Layer(comptime E: type) type {
    return struct {
        width: usize = 0,
        height: usize = 0,
        tiles: std.ArrayList(E),
        default: E,

        fn init(alloc: std.mem.Allocator, default: E) @This() {
            return .{ .tiles=std.ArrayList(E).init(alloc), .default=default };
        }

        fn resize(self: *@This(), w: usize, h: usize) !void {
            if (self.width == w and self.height == h) {
                return;
            }

            if (self.byteSize() != 0) {  
                // TODO: handle this by copying the rectangle like the real one? 
                //       but I think I never need it so remove this function and just do it on init. 
                logErr("Different sized LAYR blocks are not supported", .{});
                return Err;
            }

            // TODO: sub layers 
            
            try self.tiles.ensureTotalCapacity(w * h);
            while (self.tiles.items.len < (w * h)) {
                try self.tiles.append(self.default);
            }

            self.width = w;
            self.height = h;
        }

        fn byteSize(self: @This()) usize {
            return self.width * self.height * @sizeOf(E);
        }
    };
}

pub const Tile = extern union {
    pub const EMPTY: Tile = .{ .id=0xFFFF }; 
    pos: extern struct {
        x: u8,
        y: u8
    },
    id: u16
};

pub fn deinit(self: @This()) void {
    self.layers.deinit();
}

const MAP_ = std.mem.readIntSliceLittle(u32, "MAP ");
const TILE = std.mem.readIntSliceLittle(u32, "TILE");
const LAYR = std.mem.readIntSliceLittle(u32, "LAYR");
const MAIN = std.mem.readIntSliceLittle(u32, "MAIN");
const DATA = std.mem.readIntSliceLittle(u32, "DATA");

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
