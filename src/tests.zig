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
    try w.entities.append(.{ .pos = .{ 1, 0 }, .block = .{ .Object = .Rock }});
    try w.entities.append(.{ .pos = .{ 0, 0 }, .block = .{ .Object = .Baba }});
    try w.entities.append(.{ .pos = .{ 1, 10 }, .block = .{ .Object = .Wall }});
    try w.entities.append(.{ .pos = .{ 5, 0 }, .block = .{ .State = .You }});
    try expectEq(w.getEntity(.{ 0, 0 }).?.block, .{ .Object = .Baba });

    try w.entities.append(.{ .pos = .{ 1, 20 }, .block = .{ .Noun = .Baba }});
    w.swapNouns(.Baba, .Wall);
    try expectEq(w.getEntity(.{ 0, 0 }).?.block, .{ .Object = .Wall });
    try expectEq(w.getEntity(.{ 1, 20 }).?.block, .{ .Noun = .Baba });  // swapNouns doesn't effect the words. 
    w.swapNouns(.Wall, .Baba);
    try expectEq(w.getEntity(.{ 0, 0 }).?.block, .{ .Object = .Baba });
    try expectEq(w.getEntity(.{ 1, 10 }).?.block, .{ .Object = .Baba });

    try w.entities.append(.{ .pos = .{ 2, 20 }, .block = .Is});
    try w.entities.append(.{ .pos = .{ 3, 20 }, .block = .{ .Noun = .Wall }});
    w.calculateRules();
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

    try w.entities.append(.{ .pos = .{ 1, 5 }, .block = .{ .Noun = .Baba }});
    try w.entities.append(.{ .pos = .{ 2, 5 }, .block = .Is});
    try w.entities.append(.{ .pos = .{ 3, 5 }, .block = .{ .State = .You }});
    try w.entities.append(.{ .pos = .{ 2, 4 }, .block = .{ .Noun = .Rock }});
    try w.entities.append(.{ .pos = .{ 2, 6 }, .block = .{ .State = .Push }});
    try w.entities.append(.{ .pos = .{ 5, 0 }, .block = .{ .Noun = .Wall }});
    try w.entities.append(.{ .pos = .{ 6, 0 }, .block = .Is});
    try w.entities.append(.{ .pos = .{ 7, 0 }, .block = .{ .State = .Stop }});
    w.calculateRules();

    try w.entities.append(.{ .pos = .{ 1, 12 }, .block = .{ .Object = .Rock }});
    try w.entities.append(.{ .pos = .{ 0, 11 }, .block = .{ .Object = .Baba }});
    try w.entities.append(.{ .pos = .{ 2, 18 }, .block = .{ .Object = .Wall }});
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
    w.calculateRules();
    w.movePlayer(W.Dir.RIGHT);
    w.movePlayer(W.Dir.RIGHT);
    try expectEq(w.getEntity(.{ 3, 18 }).?.block, .{ .Object = .Baba });
    try expectEq(w.getEntity(.{ 2, 18 }).?.block, .{ .Object = .Wall });
}
