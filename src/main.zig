const std = @import("std");
const W = @import("world.zig");
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sgl = sokol.gl;
const sgapp = sokol.app_gfx_glue;
const math = @import("std").math;
const sdtx = sokol.debugtext;
const save = @import("serde/save.zig");
const official = @import("serde/official.zig");
const Img = @import("zigimg");

const SAVE_FOLDER = "zig-out";
const SAVE_FILE = SAVE_FOLDER ++ "/save.baba";

const state = struct {
    var pass_action: sg.PassAction = .{};
    var pip3d: sgl.Pipeline = .{};
    var level: W.Level = undefined;
    var initialLevel: W.Level = undefined;
    var levelIndex: usize = 0;
    var sample: sg.Sampler = undefined;
    var atlas: TextureAtlas = undefined;
    var blockTextures: official.TileSet.BlockMap(TextureAtlas.Uv) = .{};
};

const alloc = std.heap.c_allocator;

// TODO: wrap with zig calling convention func so i can use try. 
export fn init() void {
    reloadLevel(0, false) catch |err| {
        std.debug.print("parse failed! {}\n", .{err});
        state.level = loadSavedLevel(SAVE_FILE) catch defaultLevel() catch @panic("OOM");
        state.initialLevel = state.level.clone(alloc) catch @panic("OOM");
    };
   
    sg.setup(.{
        .context = sgapp.context(),
        .logger = .{ .func = slog.func },
    });
    
    sgl.setup(.{
        .logger = .{ .func = slog.func },
    });

    state.pip3d = sgl.makePipeline(.{
        .depth = .{
            .write_enabled = true,
            .compare = .LESS_EQUAL,
        },
        .cull_mode = .BACK,
    });

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
    };

    var sdtx_desc: sdtx.Desc = .{ .logger = .{ .func = slog.func } };
    sdtx_desc.fonts[0] = sdtx.fontKc854();
    sdtx.setup(sdtx_desc);

    // TODO: make these just functions that don't touch the state. 
    state.atlas = TextureAtlas.init(alloc) catch @panic("OOM");
    loadOfficialTextures() catch @panic("failed to load textures");
    state.atlas.bake();
   
    state.sample = sg.makeSampler(.{
        .min_filter = .NEAREST,
        .mag_filter = .NEAREST,
    });
}

const TextureAtlas = struct {
    pixels: []u32,
    desc: sg.ImageDesc = .{
        .width = SIZE,
        .height = SIZE,
    },
    x: usize = 0,
    y: usize = 0,
    rowHeight: usize = 0,
    img: ?sg.Image = null,

    const SIZE = 256;  // TODO: this will need to grow as i can parse more. should dynamiclly resize. 
    const Uv = struct {
        top: f32 = 0.0,
        left: f32 = 0.0,
        bottom: f32 = 1.0,
        right: f32 = 1.0,
    };

    fn init(aalloc: std.mem.Allocator) !TextureAtlas {
        return .{ .pixels= try aalloc.alloc(u32, SIZE*SIZE) };
    }

    fn add(self: *@This(), img: Img.Image) !Uv {
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

        switch (img.pixels) {
            .rgba32 => |pixelData| {
                for (0..img.height) |y| {
                    for (0..img.width) |x| {
                        const imgIndex = (y * img.height) + x;
                        const atlasIndex = ((self.y + y) * SIZE) + self.x + x;
                        self.pixels[atlasIndex] = pixelData[imgIndex].toU32Rgba();
                    }
                }
            },
            else => return error.InvalidFormat,
        }

        self.x += img.width;

        uv.right = @as(f32, @floatFromInt(self.x)) / sizef;
        uv.bottom = (yf + @as(f32, @floatFromInt(img.height))) / sizef;

        std.debug.print("({} {}) -> ({}, {})\n", .{ self.x, self.y, uv.right, uv.bottom});

        return uv;
    }

    // TODO: make this just return the img. and have this thing be a builder that doesnt need to stay around. 
    fn bake(self: *TextureAtlas) void {
        self.desc.data.subimage[0][0] = sg.asRange(self.pixels);
        // TODO: does makeImage copy the data? can i free it now?
        self.img = sg.makeImage(self.desc);
    }
};

// TODO: put these all on an atlas so I dont have to keep changing the active texture on the gpu? need uv math
fn loadOfficialTextures() !void {
    const texturesFolder = "/Users/luke/Library/Application Support/Steam/steamapps/common/Baba Is You/Baba Is You.app/Contents/Resources/Data/Sprites";
    const tiles = official.tileSet.?;  // TODO: try load it then orelse. 
    var blockIter = tiles.existingPos.iterator(.{});
    while (blockIter.next()) |i| {
        const data = tiles.posToData[i];
        const path = try std.fmt.allocPrint(W.TEMP, "{s}/{s}_0_1.png", .{ texturesFolder, data.sprite });
        const uv = loadTexture(path) catch |err| {
            std.debug.print("Failed to load {s} {}", .{ path, err });
            continue;
        };
        state.blockTextures.put(data.block, uv);
    }
}

fn loadTexture(path: []const u8) !TextureAtlas.Uv {
    const png = Img.png.PNG.formatInterface();
    const imgData = try readAlloc(path, W.TEMP);
    const wtf: []const u8 = imgData;
    var imgReader: std.io.StreamSource = .{ .const_buffer=std.io.fixedBufferStream(wtf) };
    const img = try png.readImage(W.TEMP, &imgReader);
    return state.atlas.add(img);
}

export fn evnt(event: [*c]const sapp.Event) void {
    handle_event(event.*) catch @panic("OOM");
}

fn handle_event(event: sapp.Event) !void {
    switch (event.type) {
        .KEY_DOWN => {
            switch (event.key_code) {
                .ESCAPE => sapp.requestQuit(),
                .W => try state.level.handleInput(.Up),
                .A => try state.level.handleInput(.Left),
                .S => try state.level.handleInput(.Down),
                .D => try state.level.handleInput(.Right),
                .SPACE => try state.level.handleInput(.Wait),
                .Z => {
                    // TODO: hack.
                    var hist = state.level.actionHistory.items;
                    if (hist.len > 0) {
                        var newLevel = try state.initialLevel.clone(alloc);
                        for (hist[0..hist.len-1]) |in| {
                            try newLevel.handleInput(in);
                        }
                        state.level.deinit();  // TODO: extra cringe that every undo reallocates. 
                        state.level = newLevel;
                    }
                },
                .R => {
                    try state.level.copyFrom(state.initialLevel);
                },
                .LEFT => {
                    if (state.levelIndex > 0) {
                        state.levelIndex -= 1;
                        reloadLevel(state.levelIndex, true) catch {
                            std.debug.print("Failed to load level {}\n", .{state.levelIndex});
                        };
                    }
                },
                .RIGHT => {
                    state.levelIndex += 1;
                    // TODO: split into two functions. one that does stuff with the state and wraps a pure one in official.zig 
                    reloadLevel(state.levelIndex, true) catch {
                        std.debug.print("Failed to load level {}\n", .{state.levelIndex});
                    };
                },
                else => {}
            }
        },
        .QUIT_REQUESTED => {
            saveToFile(SAVE_FILE, state.level) catch {
                std.debug.print("Failed to save.", .{});
            };
        },
        else => {}
    }
}

// TODO: move this to official.zig and just return the level obj. 
fn reloadLevel(index: usize, reset: bool) !void {
    const template = "/Users/luke/Library/Application Support/Steam/steamapps/common/Baba Is You/Baba Is You.app/Contents/Resources/Data/Worlds/baba/{}level.l";
    const path = try std.fmt.allocPrint(W.TEMP, template, .{index});
    var newLevel = try official.loadLevel(std.heap.c_allocator, path); 
    newLevel.debugPrint();
    if (reset) {  // TODO: aaaaaaa, i dont care rn
        state.level.deinit();
        state.initialLevel.deinit();
    }
    
    // TODO: dont reallocate every load. 
    state.level = newLevel;
    state.initialLevel = try newLevel.clone(std.heap.c_allocator);
}


fn loadSavedLevel(path: []const u8) !W.Level {
    const saveFile = try std.fs.cwd().openFile(path, .{});
    defer saveFile.close();
    const data = try saveFile.reader().readAllAlloc(alloc, std.math.maxInt(u16));
    defer alloc.free(data);
    return try save.loadLevel(data, alloc);
}

fn saveToFile(path: []const u8, level: W.Level) !void {
    try std.fs.cwd().makePath(SAVE_FOLDER);
    const saveFile = try std.fs.cwd().createFile(path, .{});
    defer saveFile.close();
    const data = try save.saveLevel(level, alloc);
    defer alloc.free(data);
    try saveFile.writer().writeAll(data);
}

export fn frame() void {
    const dw = sapp.widthf();
    const dh = sapp.heightf();
    sgl.viewportf(0.0, 0.0, dw, dh, true);

    // The scaling will be adjusted to always fit >= this many objects. This can change by level. 
    // Levels aren't squares, so calculate for both dimensions and use most restrictive. 
    const quadCountX: f32 = @floatFromInt(state.level.size[0]); 
    const quadCountY: f32 = @floatFromInt(state.level.size[1]); 
    const quadSizePixX = dw / quadCountX;
    const quadSizePixY = dh / quadCountY;
    const quadSizePix = @min(quadSizePixX, quadSizePixY);
    const quadWidthRat = quadSizePix / dw;
    const quadHeightRat = quadSizePix / dh;

    {
        const scale: f32 = 1.0;
        sgl.defaults();
        sgl.enableTexture();
        sgl.texture(state.atlas.img.?, state.sample);
        sgl.scale(scale, scale, 1.0);
        sgl.beginQuads(); 

        sdtx.font(0);
        sdtx.color3b(255, 128, 0);
        const charPerQuad = 3.0;
        const charSizePix = quadSizePix / charPerQuad;
        const textScale = charSizePix / 8.0;  // 1.0 means 8x8 pixel chars. 2.0 means 16x16 pixel chars. // TODO: set based on fiting 3 letters in a block 
        const logicToCharGrid = quadSizePix / charSizePix;
        sdtx.canvas(sapp.widthf() / textScale, sapp.heightf() / textScale);

        // Shows which part of the screen you can actually be in. 
        drawBackground(.{ .r=20, .g=20, .b=20 }, .{quadWidthRat, quadHeightRat}, state.level.size);


        // TODO: this is fucking insane. at least sort it instead of looping 20 times like a turtle. 
        //       this doesnt even work because it draws all the yellow then all the text beacuse of the clever draw call coalescing. 
        //       When using textures, can use the z coord on the vertex. 
        for (0..21) |currentLayer| {
            for (state.level.entities.items) |e| {
                // TODO: cope with not having loaded the tileSet. 
                const myLayer = official.tileSet.?.blockToLayer.get(e.block) orelse 20;
                if (myLayer != currentLayer) {
                    continue;
                }

                if (state.blockTextures.get(e.block)) |uv| {
                    drawOneQuad(e.pos, uv, .{quadWidthRat, quadHeightRat});
                }

                const x = @as(f32, @floatFromInt(e.pos[0]));
                const y = @as(f32, @floatFromInt(e.pos[1]));
                sdtx.origin(x * logicToCharGrid, y * logicToCharGrid);
                sdtx.pos(0, 0);
                const s = e.block.name();
                switch (s.len) {
                    0...3 => {
                        sdtx.print("{s}", .{s});
                    },
                    4 => {
                        sdtx.print("{s}", .{s[0..2]});
                        sdtx.pos(0, 1);
                        sdtx.print("{s}", .{s[2..]});
                    },
                    5...6 => {
                        sdtx.print("{s}", .{s[0..3]});
                        sdtx.pos(0, 1);
                        sdtx.print("{s}", .{s[3..]});
                    },
                    else => {
                        std.debug.panic("TODO: long word", .{});
                    }
                }
            }
        }
        

        switch (state.level.state) {
            .Win => alertText("You Win!"),
            .Lose => alertText("Press 'r' to restart."),
            .None => {},
        }

        sgl.end();
    }

    sg.beginDefaultPass(state.pass_action, sapp.width(), sapp.height());
    sgl.draw();
    sdtx.draw();
    sg.endPass();
    sg.commit();

    _ = W.frameArena.reset(.retain_capacity);
}

fn alertText(comptime msg: []const u8) void {
    const winTextScale = 3.0;
    sdtx.color3b(255, 0, 0);
    sdtx.canvas(sapp.widthf() / winTextScale, sapp.heightf() / winTextScale);
    sdtx.origin(0, 0);
    sdtx.pos(0, 0);
    sdtx.print(msg, .{});
}

const Colour = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255  // TODO: I feel like this doesn't work. 
};

// Requires context setup before call. 
fn drawOneQuaBoring(pos: W.Pos, c: Colour, size: @Vector(2, f32)) void {
    const x = @as(f32, @floatFromInt(pos[0]));
    const y = @as(f32, @floatFromInt(pos[1]));
    // Changing coordinate systems: 
    // - right/bottom are offset 1 (logic) unit to the next grid cell. 
    // - size is scaled because its a percent of the screen the quad should take up but we want in range (-1, 1).
    // - final result is offset 1 (device) unit to move origin from center to top left. 
    // - y is flipped
    const left = (x * (size[0] * 2.0)) - 1;
    const right = ((x + 1) * (size[0] * 2.0)) - 1;
    const top = (-y * (size[1] * 2.0)) + 1;
    const bottom = (-(y + 1) * (size[1] * 2.0)) + 1;
    
    // Center is (0, 0). Screen is 2x2. Top left is (-1, 1). Those are affected by the scale.
    sgl.v2fC4b(left, bottom, c.r, c.g, c.b, c.a);
    sgl.v2fC4b(right, bottom, c.r, c.g, c.b, c.a);
    sgl.v2fC4b(right, top, c.r, c.g, c.b, c.a);
    sgl.v2fC4b(left, top, c.r, c.g, c.b, c.a);
}

fn drawOneQuad(pos: W.Pos, uv: TextureAtlas.Uv, size: @Vector(2, f32)) void {
    const x = @as(f32, @floatFromInt(pos[0]));
    const y = @as(f32, @floatFromInt(pos[1]));
    // Changing coordinate systems: 
    // - right/bottom are offset 1 (logic) unit to the next grid cell. 
    // - size is scaled because its a percent of the screen the quad should take up but we want in range (-1, 1).
    // - final result is offset 1 (device) unit to move origin from center to top left. 
    // - y is flipped
    const left = (x * (size[0] * 2.0)) - 1;
    const right = ((x + 1) * (size[0] * 2.0)) - 1;
    const top = (-y * (size[1] * 2.0)) + 1;
    const bottom = (-(y + 1) * (size[1] * 2.0)) + 1;
    
    // Center is (0, 0). Screen is 2x2. Top left is (-1, 1). Those are affected by the scale.
    sgl.v2fT2f(left, bottom, uv.left, uv.bottom);
    sgl.v2fT2f(right, bottom, uv.right, uv.bottom);
    sgl.v2fT2f(right, top, uv.right, uv.top);
    sgl.v2fT2f(left, top, uv.left, uv.top);
}


// TODO: one func used by ^ that lets you give start and stop pos in logic space. 
fn drawBackground(c: Colour, size: @Vector(2, f32), worldSize: W.Pos) void {
    const w = @as(f32, @floatFromInt(worldSize[0]));
    const h = @as(f32, @floatFromInt(worldSize[1]));
    const left = -1.0;
    const right = (w * (size[0] * 2.0)) - 1;
    const top = 1.0;
    const bottom = (-h * (size[1] * 2.0)) + 1;
    
    // Center is (0, 0). Screen is 2x2. Top left is (-1, 1). Those are affected by the scale.
    sgl.v2fC4b(left, bottom, c.r, c.g, c.b, c.a);
    sgl.v2fC4b(right, bottom, c.r, c.g, c.b, c.a);
    sgl.v2fC4b(right, top, c.r, c.g, c.b, c.a);
    sgl.v2fC4b(left, top, c.r, c.g, c.b, c.a);
}


export fn cleanup() void {
    sgl.shutdown();
    sg.shutdown();
}

pub fn main() !void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = evnt,
        .width = 512,
        .height = 512,
        .sample_count = 4,
        .icon = .{ .sokol_default = true },
        .window_title = "BabaIsCloned",
        .logger = .{ .func = slog.func },
    });
}

fn defaultLevel() !W.Level {
    var w = W.Level.init(std.heap.c_allocator, .{ 10, 10 });
    try w.addEntity(.{ 1, 5 }, .{ .Noun = .Baba });
    try w.addEntity(.{ 2, 5 }, .{ .Connect = .Is });
    try w.addEntity(.{ 3, 5 }, .{ .State = .You });
    try w.addEntity(.{ 2, 4 }, .{ .Noun = .Rock });
    try w.addEntity(.{ 2, 6 }, .{ .State = .Push });
    try w.addEntity(.{ 5, 0 }, .{ .Noun = .Wall });
    try w.addEntity(.{ 6, 0 }, .{ .Connect = .Is });
    try w.addEntity(.{ 7, 0 }, .{ .State = .Stop });
    try w.addEntity(.{ 5, 2 }, .{ .Object = .Rock });
    try w.addEntity(.{ 5, 1 }, .{ .Object = .Baba });
    try w.addEntity(.{ 5, 8 }, .{ .Object = .Wall });
    w.updateRules();
    return w;
}

pub fn readAlloc(absPath: []const u8, aalloc: std.mem.Allocator) ![]u8 {
    const file = try std.fs.openFileAbsolute(absPath, .{});
    defer file.close();
    return try file.reader().readAllAlloc(aalloc, std.math.maxInt(u32));
}