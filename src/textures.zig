const std = @import("std");
const W = @import("world.zig");
const Img = @import("zigimg");
const sokol = @import("sokol");
const sg = sokol.gfx;
const Colour = @import("main.zig").Colour;
const TileSet = @import("serde/TileSet.zig");
const logErr = @import("serde/official.zig").logErr;
const require = @import("serde/official.zig").require;
pub const UvMap = TileSet.BlockMap(TextureAtlas.Uv);

const AtlasResult = struct {
    atlas: TextureAtlas,
    map: UvMap = .{},
};

// Caller owns the returned TextureAtlas.
pub fn loadOfficialTextures(tiles: TileSet, texturesFolder: []const u8, alloc: std.mem.Allocator) !AtlasResult {
    var self: AtlasResult = .{ .atlas= try TextureAtlas.init(alloc) };
    var blockIter = tiles.existingPos.iterator(.{});
    while (blockIter.next()) |i| {
        const data = tiles.posToData[i];
        const path = try std.fmt.allocPrint(W.TEMP, "{s}/{s}_0_1.png", .{ texturesFolder, data.sprite });
        const img = readPngFile(path) catch |err| {
            logErr("Failed to load {s} {}", .{ path, err });
            continue;
        };
        const uv = try self.atlas.add(img); 
        try require(!self.map.contains(data.block), "Tried to overwrite texture for {}", .{ data.block });
        self.map.put(data.block, uv);
    }

    return self;
}

/// Obvious motivation for this is sgl's simple interface doesn't seem to allow switching textures part way through.
/// As a bonus, its faster to just give one texture to the gpu, instead of switching it with many draw calls. 
pub const TextureAtlas = struct {
    pixels: []u32,
    x: usize = 0,
    y: usize = 0,
    rowHeight: usize = 0,

    const SIZE = 256;  // TODO: this will need to grow as i can parse more. should dynamiclly resize. 
    pub const Uv = struct {
        top: f32 = 0.0,
        left: f32 = 0.0,
        bottom: f32 = 1.0,
        right: f32 = 1.0,
    };

    pub fn init(aalloc: std.mem.Allocator) !TextureAtlas {
        var self: @This() = .{ .pixels= try aalloc.alloc(u32, SIZE*SIZE) };
        // TODO: should ahave an all white slot for drawing the background. 
        for (0..SIZE*SIZE) |i| {  // TODO: remove? 
            self.pixels[i] = 0xFFFFFFFF;  // TODO: if not 0, you can see a little bit of edge around the guy. suggests I need some padding regardless if I cant trust my uv calculations to have no error. is it just from floats? 
        }
        return self;
    }

    /// Returns an error if the image is too big for the atlas or an unknown pixel format. 
    pub fn add(self: *@This(), img: Img.Image) !Uv {
        if (img.width > SIZE) {
            return error.TooBig;
        }
        if (self.x + img.width > SIZE) {
            self.x = 0;
            self.y += self.rowHeight;
            self.rowHeight = 0;
        }

        if (img.height > SIZE - self.y) {
            return error.TooBig;
        }

        const sizef: f32 = @floatFromInt(SIZE);
        const xf: f32 = @floatFromInt(self.x);
        const yf: f32 = @floatFromInt(self.y);
        var uv: Uv = .{ .top=yf/sizef, .left=xf/sizef};

        self.rowHeight = @max(self.rowHeight, img.height);

        // TODO: figure out which places I need to specify pixel format for sgl instead of relying on default being ABGR 
        switch (img.pixels) {
            .rgba32 => |pixelData| {
                for (0..img.height) |y| {
                    for (0..img.width) |x| {
                        const imgIndex = (y * img.height) + x;
                        const atlasIndex = ((self.y + y) * SIZE) + self.x + x;

                        // Note this is not .toU32Rgba()
                        const data = @as(u32, pixelData[imgIndex].a) << 24 |
                            @as(u32, pixelData[imgIndex].b) << 16 |
                            @as(u32, pixelData[imgIndex].g) << 8 |
                            @as(u32, pixelData[imgIndex].r);
                        self.pixels[atlasIndex] = data;
                    }
                }
            },
            else => return error.InvalidFormat,
        }

        self.x += img.width;

        uv.right = @as(f32, @floatFromInt(self.x)) / sizef;
        uv.bottom = (yf + @as(f32, @floatFromInt(img.height))) / sizef;

        return uv;
    }

    pub fn bake(self: TextureAtlas) sg.Image {
        var desc: sg.ImageDesc = .{
            .width = SIZE,
            .height = SIZE,
        };
        desc.data.subimage[0][0] = sg.asRange(self.pixels);
        // TODO: does makeImage copy the data? can i free it now?
        return sg.makeImage(desc);
    }
    
    // TODO: debug save to file? 
};

pub const ColourSet = struct {
    const width: usize = 7;
    const height: usize = 5;
    data: [width * height] Colour = undefined,

    pub fn load(img: Img.Image) !ColourSet {
        var self: ColourSet = .{};
        switch (img.pixels) {
            .rgba32 => |pixels| {
                const tileWidth = img.width / width;
                const tileHeight = img.height / height;
                for (0..height) |y|{
                    for (0..width) |x|{
                        // TOOD: bounds check return error.
                        const tileIndex = (y * width) + x;
                        const pixelIndex = (y * tileHeight * img.width) + (x * tileWidth);
                        const c = pixels[pixelIndex];
                        self.data[tileIndex] = .{ .r=c.r, .g=c.g, .b=c.b };
                    }
                }
            },
            else => return error.InvalidFormat,
        }
        return self;
    }

    // TODO: take TilePos? 
    pub fn get(self: ColourSet, x: u8, y: u8) Colour {
        return self.data[(y * width) + x];
    }
};

// Reads into the Temp allocator since sokol wants to own a copy of the data anyway. 
pub fn readPngFile(path: []const u8) !Img.Image {
    const png = Img.png.PNG.formatInterface();
    const imgData = try readAlloc(path, W.TEMP);
    const wtf: []const u8 = imgData;  // TODO: why do you no are have cast 
    var imgReader: std.io.StreamSource = .{ .const_buffer=std.io.fixedBufferStream(wtf) };
    return try png.readImage(W.TEMP, &imgReader);
}

pub fn readAlloc(absPath: []const u8, aalloc: std.mem.Allocator) ![]u8 {
    const file = try std.fs.openFileAbsolute(absPath, .{});
    defer file.close();
    return try file.reader().readAllAlloc(aalloc, std.math.maxInt(u32));
}
