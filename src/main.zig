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
const save = @import("save.zig");

const SAVE_FOLDER = "zig-out";
const SAVE_FILE = SAVE_FOLDER ++ "/save.baba";

const state = struct {
    var pass_action: sg.PassAction = .{};
    var pip3d: sgl.Pipeline = .{};
    var level: W.Level = undefined;
    var initialLevel: W.Level = undefined;
};

const alloc = std.heap.c_allocator;

// TODO: wrap with zig calling convention func so i can use try. 
export fn init() void {
    if (@import("official.zig").loadLevel(std.heap.c_allocator)) |levelt| {
        levelt.debugPrint();
    } else |err| {
        std.debug.print("parse failed! {}\n", .{err});
    }
   
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

    state.level = loadSavedLevel(SAVE_FILE) catch defaultLevel() catch @panic("OOM");
    state.initialLevel = state.level.clone(alloc) catch @panic("OOM");
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
    // frame time 'normalized' to 60fps
    const dt: f32 = @floatCast(sapp.frameDuration() * 60);
    _ = dt;

    // The scaling will be adjusted to always fit >= this many objects. This can change by level. 
    const quadCount: f32 = @floatFromInt(@max(state.level.size[0], state.level.size[1])); 

    const dw = sapp.widthf();
    const dh = sapp.heightf();
    sgl.viewportf(0.0, 0.0, dw, dh, true);
    const screenSize = @min(dw, dh);
    const quadSizePix = screenSize / quadCount;
    const quadWidthRat = quadSizePix / dw;
    const quadHeightRat = quadSizePix / dh;


    {
        const scale: f32 = 1.0;
        sgl.defaults();
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

        for (state.level.entities.items) |e| {
            const colour: Colour = if (e.block.isText()) .{ .r=255, .g=255, .b=255 } else .{ .r=255, .g=255, .b=128 };
            drawOneQuad(e.pos, colour, .{quadWidthRat, quadHeightRat});

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
};

// Requires context setup before call. 
fn drawOneQuad(pos: W.Pos, c: Colour, size: @Vector(2, f32)) void {
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
    sgl.v2fC3b(left, bottom, c.r, c.g, c.b);
    sgl.v2fC3b(right, bottom, c.r, c.g, c.b);
    sgl.v2fC3b(right, top, c.r, c.g, c.b);
    sgl.v2fC3b(left, top, c.r, c.g, c.b);
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
    sgl.v2fC3b(left, bottom, c.r, c.g, c.b);
    sgl.v2fC3b(right, bottom, c.r, c.g, c.b);
    sgl.v2fC3b(right, top, c.r, c.g, c.b);
    sgl.v2fC3b(left, top, c.r, c.g, c.b);
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
    try w.addEntity(.{ 2, 5 }, .Is);
    try w.addEntity(.{ 3, 5 }, .{ .State = .You });
    try w.addEntity(.{ 2, 4 }, .{ .Noun = .Rock });
    try w.addEntity(.{ 2, 6 }, .{ .State = .Push });
    try w.addEntity(.{ 5, 0 }, .{ .Noun = .Wall });
    try w.addEntity(.{ 6, 0 }, .Is);
    try w.addEntity(.{ 7, 0 }, .{ .State = .Stop });
    try w.addEntity(.{ 5, 2 }, .{ .Object = .Rock });
    try w.addEntity(.{ 5, 1 }, .{ .Object = .Baba });
    try w.addEntity(.{ 5, 8 }, .{ .Object = .Wall });
    w.updateRules();
    return w;
}
