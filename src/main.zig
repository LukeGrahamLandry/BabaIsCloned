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


const state = struct {
    var pass_action: sg.PassAction = .{};
    var pip3d: sgl.Pipeline = .{};
    var level: W.Level = undefined;
};

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

    state.level = defaultLevel() catch @panic("OOM");
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

        for (state.level.entities.items) |e| {
            drawOneQuad(e.pos, .{ .r=255, .g=0, .b=255 }, .{quadWidthRat, quadHeightRat});
        }

        sgl.end();
    }

    const invTextScale = 2.0;  // 1.0 means 8x8 pixel chars. 0.5 means 16x16 pixel chars. 
    sdtx.canvas(sapp.widthf() * invTextScale, sapp.heightf() * invTextScale);
    sdtx.origin(3, 3);

    const font = 0;
    sdtx.font(font);
    sdtx.color3b(255, 128, 0);
    sdtx.print("Hello '{}'!lk;dsk;lask;ladk;ldsak;ldas;kldas;klad;ksl;kdlasl;kasd;kdlaskl;ads\n", .{1234});
    sdtx.moveY(2);

    sg.beginDefaultPass(state.pass_action, sapp.width(), sapp.height());
    sgl.draw();
    sdtx.draw();
    sg.endPass();
    sg.commit();
}


const Color = struct {
    r: u8,
    g: u8,
    b: u8,
};

// Requires context setup before call. 
fn drawOneQuad(pos: W.Pos, c: Color, size: @Vector(2, f32)) void {
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
    var w = W.Level.init(std.heap.c_allocator, .{ 10, 20 });
    try w.addEntity(.{ 1, 5 }, .{ .Noun = .Baba });
    try w.addEntity(.{ 2, 5 }, .Is);
    try w.addEntity(.{ 3, 5 }, .{ .State = .You });
    try w.addEntity(.{ 2, 4 }, .{ .Noun = .Rock });
    try w.addEntity(.{ 2, 6 }, .{ .State = .Push });
    try w.addEntity(.{ 5, 0 }, .{ .Noun = .Wall });
    try w.addEntity(.{ 6, 0 }, .Is);
    try w.addEntity(.{ 7, 0 }, .{ .State = .Stop });
    return w;
}
