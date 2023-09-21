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


const state = struct {
    var pass_action: sg.PassAction = .{};
    var pip3d: sgl.Pipeline = .{};
    var level: W.Level = undefined;
    var initialLevel: W.Level = undefined;
};

const alloc = std.heap.c_allocator;

export fn init() void {
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

    state.level = loadSavedLevel("save.baba") catch defaultLevel() catch @panic("OOM");
    state.initialLevel = state.level.clone(alloc) catch @panic("OOM");
}

export fn event_handler(event: [*c]const sapp.Event) void {
    switch (event.*.type) {
        .KEY_DOWN => {
            switch (event.*.key_code) {
                .ESCAPE => sapp.requestQuit(),
                .W => state.level.handleInput(.Up) catch @panic("OOM"),
                .A => state.level.handleInput(.Left) catch @panic("OOM"),
                .S => state.level.handleInput(.Down) catch @panic("OOM"),
                .D => state.level.handleInput(.Right) catch @panic("OOM"),
                .SPACE => state.level.handleInput(.Wait) catch @panic("OOM"),
                .Z => {
                    // TODO: hack.
                    var hist = state.level.actionHistory.items;
                    if (hist.len > 0) {
                        var newLevel = state.initialLevel.clone(alloc) catch @panic("OOM");
                        for (hist[0..hist.len-1]) |in| {
                            newLevel.handleInput(in) catch @panic("OOM");
                        }
                        state.level.deinit();  // TODO: extra cringe that every undo reallocates. 
                        state.level = newLevel;
                    }
                },
                else => {}
            }
        },
        .QUIT_REQUESTED => {
            saveToFile("save.baba", state.level) catch {
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
        const invTextScale = 1.0;  // 1.0 means 8x8 pixel chars. 0.5 means 16x16 pixel chars. // TODO: set based on fiting 3 letters in a block 
        const pixToCharGrid = 1.0 / 8.0 / invTextScale;
        const logicToCharGrid = quadSizePix * pixToCharGrid;
        sdtx.canvas(sapp.widthf() * invTextScale, sapp.heightf() * invTextScale);

        for (state.level.entities.items) |e| {
            const colour: Colour = if (e.block.isText()) .{ .r=255, .g=255, .b=255 } else .{ .r=255, .g=255, .b=128 };
            drawOneQuad(e.pos, colour, .{quadWidthRat, quadHeightRat});

            const x = @as(f32, @floatFromInt(e.pos[0]));
            const y = @as(f32, @floatFromInt(e.pos[1]));
            sdtx.origin(x * logicToCharGrid, y * logicToCharGrid);
            sdtx.pos(0, 0);
            const s = e.block.name();
            if (s.len > 2) {
                sdtx.print("{s}", .{s[0..2]});
                sdtx.pos(0, 1);
                sdtx.print("{s}", .{s[2..]});
            } else {
                sdtx.print("{s}", .{s});
            }
        }

        sgl.end();
    }

    sg.beginDefaultPass(state.pass_action, sapp.width(), sapp.height());
    sgl.draw();
    sdtx.draw();
    sg.endPass();
    sg.commit();
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

export fn cleanup() void {
    sgl.shutdown();
    sg.shutdown();
}


pub fn main() !void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event_handler,
        .width = 512,
        .height = 512,
        .sample_count = 4,
        .icon = .{ .sokol_default = true },
        .window_title = "BabaIsCloned",
        .logger = .{ .func = slog.func },
    });
}



test {
    _ = @import("tests.zig");
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
