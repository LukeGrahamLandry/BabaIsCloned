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
const Textures = @import("textures.zig");
const TestIter = @import("serde/TestIter.zig");
const logErr = std.log.scoped(.tilemap).debug;

const SAVE_FOLDER = "zig-out";
const SAVE_FILE = SAVE_FOLDER ++ "/save.baba";

const state = struct {
    var pass_action: sg.PassAction = .{};
    var pip3d: sgl.Pipeline = .{};
    var level: W.Level = undefined;
    var initialLevel: W.Level = undefined;
    var levelIndex: usize = 0;
    var sample: sg.Sampler = undefined;
    var atlas: sg.Image = undefined;
    var blockTextures: Textures.UvMap = .{};
    var pallet: Textures.ColourSet = .{};
    var tests: ?TestIter = null;
};

const alloc = std.heap.c_allocator;

// TODO: wrap with zig calling convention func so i can use try. 
export fn init() void {
    reloadLevel(0, false) catch |err| {
        logErr("parse failed! {}\n", .{err});
        state.level = loadSavedLevel(SAVE_FILE) catch W.defaultLevel() catch @panic("OOM");
        state.initialLevel = state.level.clone(alloc) catch @panic("OOM");
    };
    
    // TODO: could set the limits much lower than defaults if i wanted to be obsessive about using tiny memory. 
    sg.setup(.{
        .context = sgapp.context(),
        .logger = .{ .func = slog.func },
    });
    sgl.setup(.{
        .logger = .{ .func = slog.func },
    });


    var pipeDesc: sg.PipelineDesc = .{
        .depth = .{
            .write_enabled = true,
            .compare = .LESS_EQUAL,
        },
        .cull_mode = .BACK,
        // This makes transparency work with different z coordinates
        // Without it, if the front thing is drawn before the back thing, the front transparent parts are just solid black.
        .alpha_to_coverage_enabled = true,
    };
    
    // This makes transparency work (instead of just ignoring alpha)
    pipeDesc.colors[0].blend = .{
        .enabled = true,
        // NOT *_factor_alpha! We want to apply a factor TO rgb, the factor is based on the alpha. 
        .src_factor_rgb = .SRC_ALPHA,
        .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
    };

    state.pip3d = sgl.makePipeline(pipeDesc);

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
    };

    var sdtx_desc: sdtx.Desc = .{ .logger = .{ .func = slog.func } };
    sdtx_desc.fonts[0] = sdtx.fontKc854();
    sdtx.setup(sdtx_desc);

    const texturesFolder = "/Users/luke/Library/Application Support/Steam/steamapps/common/Baba Is You/Baba Is You.app/Contents/Resources/Data/Sprites";
    const tiles = official.tileSet.?;  // TODO: try load it then orelse. 
    const atlas = Textures.loadOfficialTextures(tiles, texturesFolder, W.TEMP) catch @panic("failed to load textures");
    state.atlas = atlas.atlas.bake();
    state.blockTextures = atlas.map;
    
    const palletPath = "/Users/luke/Library/Application Support/Steam/steamapps/common/Baba Is You/Baba Is You.app/Contents/Resources/Data/Palettes/default.png";
    state.pallet = Textures.ColourSet.load(Textures.readPngFile(palletPath) catch @panic("failed to load pallet")) catch @panic("failed to load pallet");
   
    state.sample = sg.makeSampler(.{
        .min_filter = .LINEAR,
        .mag_filter = .LINEAR,
    });

    _ = W.frameArena.reset(.retain_capacity);
}

export fn evnt(event: [*c]const sapp.Event) void {
    handle_event(event.*) catch @panic("OOM");
}

fn handle_event(event: sapp.Event) !void {
    if (event.type == .KEY_DOWN and event.key_code == .ESCAPE) {
        sapp.requestQuit();
    } else if (event.type == .QUIT_REQUESTED) {
        saveToFile(SAVE_FILE, state.level) catch {
            logErr("Failed to save.", .{});
        };
    } else if (state.tests) |*tests| {
        try handleTestInput(event, tests);
    } else {
        try handleGameInput(event);
    }
}

fn handleTestInput(event: sapp.Event, tests: *TestIter) !void {
     if (event.type != .KEY_DOWN) {
        return;
    }

    // TODO: ,. to move between tests (need to be able to reset level). ad to move between actions (need to be able to undo). space to pause. 
    switch (event.key_code) {
        .P => {
            tests.deinit();
            state.tests = null;
        },
        .MINUS => tests.speed += 1,
        .EQUAL => {
            if (tests.speed > 1) {
                tests.speed -= 1;
            }
        },
        else => {}
    }
}

fn handleGameInput(event: sapp.Event) !void {
    if (event.type != .KEY_DOWN) {
        return;
    }

    switch (event.key_code) {
        .W, .UP => try state.level.handleInput(.Up),
        .A, .LEFT => try state.level.handleInput(.Left),
        .S, .DOWN => try state.level.handleInput(.Down),
        .D, .RIGHT => try state.level.handleInput(.Right),
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
        .COMMA => {
            if (state.levelIndex > 0) {
                state.levelIndex -= 1;
                reloadLevel(state.levelIndex, true) catch |err| {
                    logErr("Failed to load level {} {}\n", .{state.levelIndex, err});
                };
            }
        },
        .PERIOD => {
            state.levelIndex += 1;
            // TODO: split into two functions. one that does stuff with the state and wraps a pure one in official.zig 
            reloadLevel(state.levelIndex, true) catch |err| {
                logErr("Failed to load level {} {}\n", .{state.levelIndex, err});
            };
        },
        .T => {
            try TestIter.saveTestRoute(state.levelIndex, state.level);
        },
        .P => {
            std.debug.assert(state.tests == null); 
            // TODO: need a way to change speed or pause and move back and forth manually or to specific level
            //       does it need to be a real gui instead of rememebering keyboard shortcuts? 
            state.tests = .{ .arena=std.heap.ArenaAllocator.init(std.heap.c_allocator) };
            try state.tests.?.load();
        },
        else => {}
    }
}

// TODO: move this to official.zig and just return the level obj. 
fn reloadLevel(index: usize, reset: bool) !void {
    const template = "/Users/luke/Library/Application Support/Steam/steamapps/common/Baba Is You/Baba Is You.app/Contents/Resources/Data/Worlds/baba/{}level.l";
    const path = try std.fmt.allocPrint(W.TEMP, template, .{index});
    var newLevel = try official.loadLevel(std.heap.c_allocator, path); 
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

const PosF = @Vector(2, f32);
const Sizes = struct { quadNorm: PosF, quadPix: f32 };

fn calcSizes(levelSize: W.Pos) Sizes {
    // The scaling will be adjusted to always fit >= this many objects. This can change by level. 
    // Levels aren't squares, so calculate for both dimensions and use most restrictive. 
    const dw = sapp.widthf();
    const dh = sapp.heightf();
    const quadCountX: f32 = @floatFromInt(levelSize[0]); 
    const quadCountY: f32 = @floatFromInt(levelSize[1]); 
    const quadSizePixX = dw / quadCountX;
    const quadSizePixY = dh / quadCountY;
    const quadPix = @min(quadSizePixX, quadSizePixY);
    const quadWidthRat = quadPix / dw;
    const quadHeightRat = quadPix / dh;
    return .{ .quadNorm = .{quadWidthRat, quadHeightRat}, .quadPix=quadPix };
}

// TODO: system for logging temp messages on screen. 
export fn frame() void {
    var level = &state.level;

    // If tests are running, render that level instead. 
    if (state.tests) |*tests| {
        if (tests.tick()) {
            level = tests.getLevel();
        } else {
            tests.deinit();
            state.tests = null;
        }
    }

    const s = calcSizes(level.size);
    sdtx.font(0);
    sgl.viewportf(0.0, 0.0, sapp.widthf(), sapp.heightf(), true);
    sgl.defaults();
    sgl.loadPipeline(state.pip3d);  // activate the one with transparency enabled. 
    sgl.enableTexture();
    sgl.texture(state.atlas, state.sample);
    sgl.beginQuads(); 

    // Shows which part of the screen you can actually be in. 
    drawBackground(.{ .r=20, .g=20, .b=20 }, s.quadNorm, level.size);

    renderOfficial(level.*, s.quadNorm);
    // renderUgly(level.*, s);

    switch (level.state) {
        .Win => alertText("You Win!"),
        .Lose => alertText("Press 'r' to restart."),
        .None => {},
    }

    if (state.tests) |t| {
        renderTestOverlay(t);
    }

    sgl.end();
    sg.beginDefaultPass(state.pass_action, sapp.width(), sapp.height());
    sgl.draw();
    sdtx.draw();
    sg.endPass();
    sg.commit();

    _ = W.frameArena.reset(.retain_capacity);
}


// TODO: auto line wrapping. 
fn renderTestOverlay(t: TestIter) void {
    sdtx.color3b(0, 255, 0);
    sdtx.canvas(sapp.widthf(), sapp.heightf());
    sdtx.pos(1, 1);
    if (t.failed == 0) {
        sdtx.print("Passing {}/{}. ", .{ t.passed, t.cases.len });
    } else {
        sdtx.print("Failed {}. Passed {}/{}. ", .{ t.failed, t.passed, t.cases.len });
    }
    sdtx.color3b(0, 150, 0);
    sdtx.print("Delay: {} (control with +/-).", .{ t.speed });
    sdtx.pos(1, 2);
    if (t.testIndex < t.cases.len) {
        const str = t.cases[t.testIndex].text;
        const moveCount = t.cases[t.testIndex].actions.len;
        const moveChar = str.len - moveCount + t.actionIndex;
        sdtx.color3b(0, 150, 0);
        sdtx.print("{s}", .{ str[0..moveChar] });
        if (moveChar < str.len) {
            sdtx.color3b(255, 255, 255);
            sdtx.print("{c}", .{ str[moveChar] });
            sdtx.color3b(0, 150, 0);
            sdtx.print("{s}", .{ str[moveChar+1..] });
        }
    }
}

fn renderOfficial(level: W.Level, quadNorm: PosF) void {
    const invalidInfo: official.TileSet.BlockData = .{ .layer=20, .colour=.{ 4, 1 }};
    for (level.entities.items) |e| {
        // TODO: more elegant coping with not having loaded the tileSet. validate everything up front and swap to other renderer if needed. 
        const info = official.tileSet.?.blockToLayer.get(e.block) orelse invalidInfo;

        const uv = state.blockTextures.get(e.block) orelse Textures.TextureAtlas.Blank;
        const c: Colour = state.pallet.get(info.colour[0], info.colour[1]);
        drawOneQuad(e.pos, uv, c, quadNorm, info.layer);
    }
}

// TODO: auto fall back to this if data not loaded. 
fn renderUgly(level: W.Level, s: Sizes) void {
    sdtx.color3b(255, 128, 0);
    const charPerQuad = 3.0;
    const charSizePix = s.quadPix / charPerQuad;
    const textScale = charSizePix / 8.0;  // 1.0 means 8x8 pixel chars. 2.0 means 16x16 pixel chars. 
    const logicToCharGrid = s.quadPix / charSizePix;
    sdtx.canvas(sapp.widthf() / textScale, sapp.heightf() / textScale);

    const textColour: Colour = .{ .r=255, .g=255, .b=255 };
    const objColour: Colour = .{ .r=255, .g=255, .b=128 };

    for (level.entities.items) |e| {
        const c = if (e.block.isText()) textColour else objColour;
        drawOneQuad(e.pos, Textures.TextureAtlas.Blank, c, s.quadNorm, 20); 
        drawWord(e, logicToCharGrid);
    }
}

fn drawWord(e: W.Entity, logicToCharGrid: f32) void {
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

fn alertText(comptime msg: []const u8) void {
    const winTextScale = 3.0;
    sdtx.color3b(255, 0, 0);
    sdtx.canvas(sapp.widthf() / winTextScale, sapp.heightf() / winTextScale);
    sdtx.origin(0, 0);
    sdtx.pos(0, 0);
    sdtx.print(msg, .{});
}

pub const Colour = struct {
    r: u8,
    g: u8,
    b: u8,
};

// The colour tints the texture. All the game's assets are grayscale and re-themed. 
fn drawOneQuad(logicPos: W.Pos, uv: Textures.TextureAtlas.Uv, c: Colour, size: PosF, layer: u8) void {
    const x = @as(f32, @floatFromInt(logicPos[0]));
    const y = @as(f32, @floatFromInt(logicPos[1]));
    // Changing coordinate systems:logicPos
    // - right/bottom are offset 1 (logic) unit to the next grid cell. 
    // - size is scaled because its a percent of the screen the quad should take up but we want in range (-1, 1).
    // - final result is offset 1 (device) unit to move origin from center to top left. 
    // - y is flipped
    const left = (x * (size[0] * 2.0)) - 1;
    const right = ((x + 1) * (size[0] * 2.0)) - 1;
    const top = (-y * (size[1] * 2.0)) + 1;
    const bottom = (-(y + 1) * (size[1] * 2.0)) + 1;
    
    // Center is (0, 0). Screen is 2x2. Top left is (-1, 1). Those are affected by the scale.
    const z = 1.0 - (@as(f32, @floatFromInt(layer)) / 100.0);
    sgl.v3fT2fC3b(left, bottom, z, uv.left, uv.bottom, c.r, c.g, c.b);
    sgl.v3fT2fC3b(right, bottom, z, uv.right, uv.bottom, c.r, c.g, c.b);
    sgl.v3fT2fC3b(right, top, z, uv.right, uv.top, c.r, c.g, c.b);
    sgl.v3fT2fC3b(left, top, z, uv.left, uv.top, c.r, c.g, c.b);
}

fn drawBackground(c: Colour, size: @Vector(2, f32), worldSize: W.Pos) void {
    // TODO: is there a way to cast vectors? 
    const w = @as(f32, @floatFromInt(worldSize[0])) * size[0];
    const h = @as(f32, @floatFromInt(worldSize[1])) * size[1];
    drawOneQuad(.{ 0, 0 }, Textures.TextureAtlas.Blank, c, .{ w, h }, 0);
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

pub fn readAlloc(absPath: []const u8, aalloc: std.mem.Allocator) ![]u8 {
    const file = try std.fs.openFileAbsolute(absPath, .{});
    defer file.close();
    return try file.reader().readAllAlloc(aalloc, std.math.maxInt(u32));
}