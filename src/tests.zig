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

    try expectEq(w.getEntity(.{ 0, 0 }), null);
    try w.addEntity(.{ 1, 0 }, .{ .Object = .Rock });
    try w.addEntity(.{ 0, 0 }, .{ .Object = .Baba });
    try w.addEntity(.{ 1, 10 }, .{ .Object = .Wall });
    try w.addEntity(.{ 5, 0 }, .{ .State = .You });
    try expectEq(w.getEntity(.{ 0, 0 }).?.block, .{ .Object = .Baba });

    try w.addEntity(.{ 1, 20 }, .{ .Noun = .Baba });
    w.swapNouns(.Baba, .Wall);
    try expectEq(w.getEntity(.{ 0, 0 }).?.block, .{ .Object = .Wall });
    try expectEq(w.getEntity(.{ 1, 20 }).?.block, .{ .Noun = .Baba });  // swapNouns doesn't effect the words. 
    w.swapNouns(.Wall, .Baba);
    try expectEq(w.getEntity(.{ 0, 0 }).?.block, .{ .Object = .Baba });
    try expectEq(w.getEntity(.{ 1, 10 }).?.block, .{ .Object = .Baba });

    try w.addEntity(.{ 2, 20 }, .Is);
    try w.addEntity(.{ 3, 20 }, .{ .Noun = .Wall });
    w.updateRules();
    try expectEq(w.getEntity(.{ 0, 0 }).?.block, .{ .Object = .Wall });
    try expectEq(w.getEntity(.{ 1, 10 }).?.block, .{ .Object = .Wall });

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
    try expectEq(w.getEntity(.{ 0, 11 }).?.block, .{ .Object = .Baba });

    // can't go off screen
    w.movePlayer(W.Dir.LEFT);
    try expectEq(w.getEntity(.{ 0, 11 }).?.block, .{ .Object = .Baba });
    try expectEq(w.getEntity(.{ 9, 10 }), null);  // dont wrap around

    // can move to empty space
    w.movePlayer(W.Dir.RIGHT);
    try expectEq(w.getEntity(.{ 0, 11 }), null);
    try expectEq(w.getEntity(.{ 1, 11 }).?.block, .{ .Object = .Baba });

    // push something
    w.movePlayer(W.Dir.DOWN);
    try expectEq(w.getEntity(.{ 1, 11 }), null);
    try expectEq(w.getEntity(.{ 1, 12 }).?.block, .{ .Object = .Baba });
    try expectEq(w.getEntity(.{ 1, 13 }).?.block, .{ .Object = .Rock });

    // stop when hit wall
    for (0..30) |_| {
        w.movePlayer(W.Dir.DOWN);
    }
    try expectEq(w.getEntity(.{ 1, 18 }).?.block, .{ .Object = .Baba });
    try expectEq(w.getEntity(.{ 1, 19 }).?.block, .{ .Object = .Rock });

    // stop when hit stop
    w.movePlayer(W.Dir.RIGHT);
    try expectEq(w.getEntity(.{ 1, 18 }).?.block, .{ .Object = .Baba });
    try expectEq(w.getEntity(.{ 2, 18 }).?.block, .{ .Object = .Wall });

    // dont stop if not stop
    w.getEntity(.{ 6, 0 }).?.block = .{ .Object=.Wall }; // remove the Is 
    w.updateRules();
    w.movePlayer(W.Dir.RIGHT);
    w.movePlayer(W.Dir.RIGHT);
    try expectEq(w.getEntity(.{ 3, 18 }).?.block, .{ .Object = .Baba });
    try expectEq(w.getEntity(.{ 2, 18 }).?.block, .{ .Object = .Wall });
}
