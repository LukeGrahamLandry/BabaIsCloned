const std = @import("std");
const W = @import("world.zig");
const expectEq = std.testing.expectEqual;

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

    try w.addEntity(.{ 2, 20 }, .Is);
    try w.addEntity(.{ 3, 20 }, .{ .Noun = .Wall });
    w.updateRules();
    try expectOne(w, .{ 0, 0 }, .{ .Object = .Wall });
    try expectOne(w, .{ 1, 10 }, .{ .Object = .Wall });

    // const save = @import("save.zig");
    // const data = try save.saveLevel(w, std.heap.c_allocator);
    // std.debug.print("{!s}", .{data});
    // const w2 = try save.loadLevel(data, std.heap.c_allocator);
    // std.debug.print("{!s}", .{ save.saveLevel(w2, std.heap.c_allocator) });
}

test "move and push" {
    var w = W.Level.init(std.heap.c_allocator, .{ 10, 20 });

    try w.addEntity(.{ 1, 5 }, .{ .Noun = .Baba });
    try w.addEntity(.{ 2, 5 }, .Is);
    try w.addEntity(.{ 3, 5 }, .{ .State = .You });
    try w.addEntity(.{ 2, 4 }, .{ .Noun = .Rock });
    try w.addEntity(.{ 2, 6 }, .{ .State = .Push });
    try w.addEntity(.{ 5, 0 }, .{ .Noun = .Wall });
    try w.addEntity(.{ 6, 0 }, .Is);
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
