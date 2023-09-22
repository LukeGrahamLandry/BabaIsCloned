const std = @import("std");
const W = @import("world.zig");
const str = std.ArrayList(u8);
const VERSION: u32 = 1;

// TODO: this format doesnt work because multiple dudes are allowed in one square. 
// TODO: split pallet so tests dont have to repeat it many times 
pub fn saveLevel(self: W.Level, alloc: std.mem.Allocator) ![] const u8 {
    var header = str.init(alloc);
    const len = (self.size[0] + 1) * self.size[1];
    var body = try str.initCapacity(alloc, @intCast(len));
    var nouns: std.EnumMap(W.Noun, u8) = .{};
    var states: std.EnumMap(W.State, u8) = .{};

    for (0..@intCast(self.size[1])) |y| {
        for (0..@intCast(self.size[0])) |x| {
            _ = x;
            try body.append('-');
            _ = y;
        }
        try body.append('\n');
    }

    for (self.entities.items) |e| {
        const index = e.pos[1] * (self.size[0] + 1) + e.pos[0];
        const c: u8 = switch (e.block) {
            .Noun => |noun| b:  {
                break :b getOrAdd(W.Noun, letters, &nouns, noun);
            },
            .Object => |noun| b: {
                break :b std.ascii.toUpper(getOrAdd(W.Noun, letters, &nouns, noun));
            },
            .State => |state| b: {
                break :b getOrAdd(W.State, numbers, &states, state);
            },
            .Is => '=',
            .And => '+',
        };
        body.items[@intCast(index)] = c;
    }

    var writer = header.writer();
    try writer.print("{}\nNOUNS\n", .{VERSION});

    var iter = nouns.iterator();
    while (iter.next()) |e| {
        try writer.print("{c} {s}\n", .{ e.value.*, @tagName(e.key) });
    }

    var iter2 = states.iterator();
    try writer.print("STATES\n", .{});
    while (iter2.next()) |e| {
        try writer.print("{c} {s}\n", .{ e.value.*, @tagName(e.key) });
    }
    try writer.print("MAP\n", .{});
    try header.appendSlice(body.items);

    body.deinit();
    return try header.toOwnedSlice();
}


const ParseErr = error.LevelParseFailed;

// TODO: combine the header stuff into a pallet so tests can share
pub fn loadLevel(data: [] const u8, alloc: std.mem.Allocator) !W.Level {
    var self = W.Level.init(alloc, .{ 0, 0 });
    var lines = std.mem.splitScalar(u8, data, '\n');

    const verStr = lines.next() orelse return ParseErr;
    const version = std.fmt.parseInt(u32, verStr, 10) catch return ParseErr;
    if (version != VERSION) {
        return ParseErr;
    }

    const valid = std.mem.eql(u8, lines.next() orelse return ParseErr, "NOUNS");
    if (!valid) {
        return ParseErr;
    }

    var nouns = [_] ?W.Noun { null } ** 255;
    var states = [_] ?W.State { null } ** 255;

    while (lines.next()) |line| {
        if (std.mem.eql(u8, line, "STATES")) {
            break;
        }

        const c = line[0];
        const name = line[2..];
        const value = enumFromTagName(W.Noun, name) orelse return ParseErr;
        nouns[@intCast(c)] = value;
    }

    while (lines.next()) |line| {
        if (std.mem.eql(u8, line, "MAP")) {
            break;
        }

        const c = line[0];
        const name = line[2..];
        const value = enumFromTagName(W.State, name) orelse return ParseErr;
        states[@intCast(c)] = value;
    }

    var pos: W.Pos = .{ 0, 0 };
    while (lines.next()) |line| {
        if (line.len == 0) {
            break;
        }

        pos[0] = 0;
        defer pos[1] += 1;
        for (line) |c| {
            defer pos[0] += 1;

            if (c == '-') {
                continue;
            }

            if (std.ascii.isUpper(c)) {
                const index = std.ascii.toLower(c);
                const noun = nouns[index] orelse return ParseErr;
                try self.addEntity(pos, .{ .Object=noun });
            } else {
                if (nouns[c]) |noun| {
                    try self.addEntity(pos, .{ .Noun=noun });
                } else if (states[c]) |state| {
                    try self.addEntity(pos, .{ .State=state });
                } else if (c == '=') {
                    try self.addEntity(pos, .Is);
                } else if (c == '+') {
                    try self.addEntity(pos, .And);
                } else {
                    return ParseErr;
                }
            }
        }
    }

    self.size = pos;
    self.updateRules();
    return self;
    
}

// TODO: error if too many types in one pallet 
const letters = "abcdefghijklmnopqrstuvwxyz";
const numbers = "0123456789";
fn getOrAdd(comptime t: type, opts: [] const u8, map: *std.EnumMap(t, u8), noun: t) u8 {
    if (map.get(noun)) |c| {
        return c;
    } else {
        const c = opts[map.count()];
        map.put(noun, c);
        return c;
    }
}

fn enumFromTagName(comptime E: type, name: [] const u8) ?E {
    for (std.enums.values(E)) |value| {
        if (std.mem.eql(u8, @tagName(value), name)) {
            return value;
        }
    }
    return null;
}
