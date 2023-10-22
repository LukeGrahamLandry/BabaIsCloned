const std = @import("std");
const W = @import("../world.zig");
const TestIter = @This();
const logErr = std.log.scoped(.tilemap).debug;
const s = @import("save.zig");

pub const TestCase = struct {
    actions: []const W.Input,
    level: W.Level,
    endState: W.GameState,
    text: []const u8,
};

// TODO: this leaks stuff if error
pub fn loadTests(alloc: std.mem.Allocator) ![]TestCase {
    var file = try std.fs.cwd().openFile(testRoutesPath, .{});
    defer file.close();
    var tests = std.ArrayList(TestCase).init(alloc);
    const data = try file.readToEndAlloc(alloc, std.math.maxInt(u16));
    const template = "/Users/luke/Library/Application Support/Steam/steamapps/common/Baba Is You/Baba Is You.app/Contents/Resources/Data/Worlds/{s}level.l";
        
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        if (line.len == 0){
            continue;
        }
        var parts = std.mem.splitScalar(u8, line, ' ');
        const fileName = parts.next().?;
        const path = try std.fmt.allocPrint(W.TEMP, template, .{fileName});
        var lvl = try @import("official.zig").loadLevel(alloc, path); 
        const endState = std.meta.stringToEnum(W.GameState, parts.next().?).?;
        const actionStr = parts.next().?;
        try tests.append(.{
            .actions = try readActionList(actionStr),
            .endState = endState,
            .level = lvl,
            .text = line
        });
    }

    const mini = try loadMiniTests(alloc);
    defer alloc.free(mini);
    try tests.appendSlice(mini);

    return try tests.toOwnedSlice();    
}

// TODO: unify the two formats of tests. official levels can have one line that says which level then all tests for that level together 
pub fn loadTestLevels(data: [] const u8, alloc: std.mem.Allocator) ![]TestCase {
    var lines = std.mem.splitScalar(u8, data, '\n');
    try s.requireCurrentVersion(&lines);
    
    try s.requireNext(&lines, "PALLET");
    _ = try s.readInt(&lines);
    const pallet = try s.TilePallet.parse(&lines);

    var cases = std.ArrayList(TestCase).init(alloc);

    // TODO: loop and load multiple. 
    var level = W.Level.init(alloc, .{ 0, 0 });    
    try s.requireNext(&lines, "TEST");
    const name = lines.next() orelse return ParseErr;
    _ = name;
    _ = try s.readInt(&lines);

    try s.requireNext(&lines, "RULES");
    level.implicitRules = try readDefaultRules(lines.next().?);
    try s.requireNext(&lines, "MAP");
    try s.readLevelMap(&level, &lines, pallet);

    try s.requireNext(&lines, "EXPECT");
    while (lines.next()) |line| {
        if (line.len == 0) {
            break;
        }
        var parts = std.mem.splitScalar(u8, line, ' ');
        const endState = std.meta.stringToEnum(W.GameState, parts.next().?).?;
        const actions = try readActionList(parts.next().?);

        try cases.append(.{ .actions=actions, .level=try level.clone(alloc), .endState=endState, .text=line });
    }
    level.deinit();

    return cases.toOwnedSlice();
}

const ParseErr = error.LevelParseFailed;
fn readDefaultRules(data: []const u8) !W.Rules {
    var self = W.Rules.init();
    var entries = std.mem.splitSequence(u8, data, ", ");
    while (entries.next()) |entry| {
        var parts = std.mem.splitScalar(u8, entry, ' ');
        const ns = parts.next() orelse return ParseErr;
        const ss = parts.next() orelse return ParseErr;
        const noun = std.meta.stringToEnum(W.Noun, ns) orelse return ParseErr;
        const state = std.meta.stringToEnum(W.State, ss) orelse return ParseErr;
        self.set(noun, state);
    }
    return self;
}


// TODO: do i want to save whole level state and check that everything matches.
//       feels less elegant and dont want to commit such a direct derivitive of the real game's data.
//       hash of it? but then you can't see the problem. 
//       currently seems like a lot could go wrong and still have the test pass. 
// TODO: runlength encoding
const testRoutesPath = "tests/levels.txt";
pub fn saveTestRoute(levelId: usize, lvl: W.Level) !void {
    var file = try std.fs.cwd().openFile(testRoutesPath, .{ .mode=.read_only });
    var testCase = std.ArrayList(u8).init(W.TEMP);
    defer testCase.deinit();
    var reader = file.reader();
    try reader.readAllArrayList(&testCase, 999999);  // TODO: how do I just append to a file. seek forward by the size: https://github.com/ziglang/zig/issues/14375
    var out = testCase.writer();
    file.close();

    const startI = testCase.items.len;

    try out.print("baba/{} {s} ", .{ levelId, @tagName(lvl.state) });
    for (lvl.actionHistory.items) |a| {
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

fn loadMiniTests(alloc: std.mem.Allocator) ![]TestCase {
    var file = try std.fs.cwd().openFile("tests/mini.txt", .{ .mode=.read_only });
    defer file.close();
    const data = try file.readToEndAlloc(alloc, std.math.maxInt(u16));
    return try loadTestLevels(data, alloc);
}
