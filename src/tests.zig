const std = @import("std");
const W = @import("world.zig");
const expectEq = std.testing.expectEqual;

// TODO: do i want to save whole level state and check that everything matches.
//       feels less elegant and dont want to commit such a direct derivitive of the real game's data.
//       hash of it? but then you can't see the problem. 
//       currently seems like a lot could go wrong and still have the test pass. 
// TODO: runlength encoding
const testRoutesPath = "tests/levels.txt";
pub fn saveTestRoute(levelId: usize, level: W.Level) !void {
    var file = try std.fs.cwd().openFile(testRoutesPath, .{ .mode=.read_only });
    var testCase = std.ArrayList(u8).init(std.heap.c_allocator);
    defer testCase.deinit();
    var reader = file.reader();
    try reader.readAllArrayList(&testCase, 999999);  // TODO: how do I just append to a file. 
    var out = testCase.writer();
    file.close();

    const startI = testCase.items.len;

    try out.print("baba/{} {s} ", .{ levelId, @tagName(level.state) });
    for (level.actionHistory.items) |a| {
        // TODO: array lookup is less annoying. or just use these bytes as the repr for the enum?
        const c = @as(u8, switch (a) {
            .Left => '<',
            .Right => '>',
            .Up => '^',
            .Down => 'v',
            .Wait => '=',
        });
        try testCase.append(c);
    }
    try testCase.append('\n');

    std.debug.print("SAVE TEST: {s}\n", .{ testCase.items[startI..] });
    var file2 = try std.fs.cwd().openFile(testRoutesPath, .{ .mode=.write_only });
    try file2.writeAll(testCase.items);
    file2.close();
}

pub const TestCase = struct {
    actions: []const W.Input,
    level: W.Level,
    endState: W.GameState,
    text: []const u8,

    pub fn deinit(self: *TestCase) void {
        // TODO
        _ = self;

    }
};

// TODO: this leaks stuff if error
pub fn loadTests() ![]TestCase {
    var file = try std.fs.cwd().openFile(testRoutesPath, .{});
    defer file.close();
    var tests = std.ArrayList(TestCase).init(std.heap.c_allocator);
    const data = try file.readToEndAlloc(std.heap.c_allocator, std.math.maxInt(u16));
    const template = "/Users/luke/Library/Application Support/Steam/steamapps/common/Baba Is You/Baba Is You.app/Contents/Resources/Data/Worlds/{s}level.l";
        
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        if (line.len == 0){
            continue;
        }
        var parts = std.mem.splitScalar(u8, line, ' ');
        const fileName = parts.next().?;
        const path = try std.fmt.allocPrint(W.TEMP, template, .{fileName});
        var level = try @import("serde/official.zig").loadLevel(std.heap.c_allocator, path); 
        const endState = std.meta.stringToEnum(W.GameState, parts.next().?).?;
        const actionStr = parts.next().?;
        try tests.append(.{
            .actions = try readActionList(actionStr),
            .endState = endState,
            .level = level,
            .text = line
        });
    }

    try tests.appendSlice(try loadMiniTests());  // TODO: leak

    return try tests.toOwnedSlice();    
}

pub fn readActionList(actionStr: []const u8) ![]W.Input {
    var actions = std.ArrayList(W.Input).init(std.heap.c_allocator);
    for (actionStr) |c| {
        const a: W.Input = switch (c) {
            '<' => .Left,
            '>' => .Right,
            '^' => .Up,
            'v' => .Down,
            '=' => .Wait,
            else => std.debug.panic("Unexpected action char: '{}'", .{c}),  // TODO: err?
        };
        try actions.append(a);
    }
    return try actions.toOwnedSlice();
}

test "replay" {
    var cases = try loadTests();
    var failed = false;
    for (cases, 0..) |*tCase, i| {
        for (tCase.actions) |a| {
            try tCase.level.handleInput(a);
        }
        if (tCase.endState != tCase.level.state) {
            std.debug.print("\n*Case {} Expected {s} but got {s}.", .{ i, @tagName(tCase.endState), @tagName(tCase.level.state) });
            failed = true;  // Want to run all tests even if one fails. 
        }
    }
    if (failed) {
        return error.TestExpectedEqual;
    }
    // TODO: leaks it
    
}

fn loadMiniTests() ![]TestCase {
    var file = try std.fs.cwd().openFile("tests/mini.txt", .{ .mode=.read_only });
    defer file.close();
    const data = try file.readToEndAlloc(std.heap.c_allocator, std.math.maxInt(u16));
    return try @import("serde/save.zig").loadTestLevels(data, std.heap.c_allocator);
}

test "world repr sanity" {
    var w = W.Level.init(std.heap.c_allocator, .{ 20, 30 });

    try expectEq(w.rules.is(.Baba, .You), false);
    w.rules.set(.Baba, .You);
    try expectEq(w.rules.is(.Baba, .You), true);
    w.rules.clear();
    try expectEq(w.rules.is(.Baba, .You), false);

    try expectOne(w, .{ 0, 0 }, null);
    try w.addEntity(.{ 1, 0 }, .{ .Object = .Rock });
    try w.addEntity(.{ 0, 0 }, .{ .Object = .Baba });
    try w.addEntity(.{ 1, 10 }, .{ .Object = .Wall });
    try w.addEntity(.{ 5, 0 }, .{ .State = .You });
    try expectOne(w, .{ 0, 0 }, .{ .Object = .Baba });

    try w.addEntity(.{ 1, 20 }, .{ .Noun = .Baba });
    w.swapNouns(.Baba, .Wall);
    try expectOne(w, .{ 0, 0 }, .{ .Object = .Wall });
    try expectOne(w, .{ 1, 20 }, .{ .Noun = .Baba });  // swapNouns doesn't effect the words. 
    w.swapNouns(.Wall, .Baba);
    try expectOne(w, .{ 0, 0 }, .{ .Object = .Baba });
    try expectOne(w, .{ 1, 10 }, .{ .Object = .Baba });

    try w.addEntity(.{ 2, 20 }, .{ .Connect = .Is });
    try w.addEntity(.{ 3, 20 }, .{ .Noun = .Wall });
    w.updateRules();
    try expectOne(w, .{ 0, 0 }, .{ .Object = .Wall });
    try expectOne(w, .{ 1, 10 }, .{ .Object = .Wall });
}

test "move and push" {
    var w = W.Level.init(std.heap.c_allocator, .{ 10, 20 });

    try w.addEntity(.{ 1, 5 }, .{ .Noun = .Baba });
    try w.addEntity(.{ 2, 5 }, .{ .Connect = .Is });
    try w.addEntity(.{ 3, 5 }, .{ .State = .You });
    try w.addEntity(.{ 2, 4 }, .{ .Noun = .Rock });
    try w.addEntity(.{ 2, 6 }, .{ .State = .Push });
    try w.addEntity(.{ 5, 0 }, .{ .Noun = .Wall });
    try w.addEntity(.{ 6, 0 }, .{ .Connect = .Is });
    try w.addEntity(.{ 7, 0 }, .{ .State = .Stop });
    w.updateRules();

    try w.addEntity(.{ 1, 12 }, .{ .Object = .Rock });
    try w.addEntity(.{ 0, 11 }, .{ .Object = .Baba });
    try w.addEntity(.{ 2, 18 }, .{ .Object = .Wall });
    try expectOne(w, .{ 0, 11 }, .{ .Object = .Baba });

    // can't go off screen
    w.movePlayer(W.Dir.LEFT);
    try expectOne(w, .{ 0, 11 }, .{ .Object = .Baba });
    try expectOne(w, .{ 9, 10 }, null);  // dont wrap around

    // can move to empty space
    w.movePlayer(W.Dir.RIGHT);
    try expectOne(w, .{ 0, 11 }, null);
    try expectOne(w, .{ 1, 11 }, .{ .Object = .Baba });

    // push something
    w.movePlayer(W.Dir.DOWN);
    try expectOne(w, .{ 1, 11 }, null);
    try expectOne(w, .{ 1, 12 }, .{ .Object = .Baba });
    try expectOne(w, .{ 1, 13 }, .{ .Object = .Rock });

    // stop when hit wall
    for (0..30) |_| {
        w.movePlayer(W.Dir.DOWN);
    }
    try expectOne(w, .{ 1, 18 }, .{ .Object = .Baba });
    try expectOne(w, .{ 1, 19 }, .{ .Object = .Rock });

    // stop when hit stop
    w.movePlayer(W.Dir.RIGHT);
    try expectOne(w, .{ 1, 18 }, .{ .Object = .Baba });
    try expectOne(w, .{ 2, 18 }, .{ .Object = .Wall });

    // dont stop if not stop
    w.getEntity(.{ 6, 0 })[0].block = .{ .Object=.Wall }; // remove the Is 
    w.updateRules();
    w.movePlayer(W.Dir.RIGHT);
    w.movePlayer(W.Dir.RIGHT);
    try expectOne(w, .{ 3, 18 }, .{ .Object = .Baba });
    try expectOne(w, .{ 2, 18 }, .{ .Object = .Wall });
}

fn expectOne(w: W.Level, pos: W.Pos, block: ?W.Block) !void {
    const cringeUnsafe = @constCast(&w);
    const found = cringeUnsafe.getEntity(pos);
    if (block) |expected| {
        try expectEq(expected, found[0].block);
        try expectEq(found.len, 1);

    } else {
        try expectEq(found.len, 0);
    }
}


test "_" {
    _ = @import("serde/LuaLexer.zig");
    _ = @import("serde/TileSet.zig");
}


pub fn readAlloc(absPath: []const u8, alloc: std.mem.Allocator) ![]u8 {
    const file = try std.fs.openFileAbsolute(absPath, .{});
    defer file.close();
    return try file.reader().readAllAlloc(alloc, std.math.maxInt(u32));
}