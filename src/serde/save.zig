const std = @import("std");
const W = @import("../world.zig");
const tests = @import("TestIter.zig");
const str = std.ArrayList(u8);
const VERSION: u32 = 2;
const logErr = std.log.scoped(.tilemap).debug;

// TODO: package all the useful functions into one serde.zig that reexports so its not a pain to import everything you need. 

// TODO: this format doesnt work because multiple dudes are allowed in one square. 
// TODO: split pallet writing into TilePallet
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
            // TODO: do stuff with tag name lookup instead. 
            .Connect => |word| switch (word) {
                .Is => '=',
                .And => '+',
            }
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
    try writer.print("\nMAP\n", .{});
    try header.appendSlice(body.items);

    body.deinit();
    return try header.toOwnedSlice();
}


const ParseErr = error.LevelParseFailed;
const Iter = std.mem.SplitIterator(u8, .scalar);
pub const TilePallet = struct {
    nouns: [255]?W.Noun = [_] ?W.Noun { null } ** 255,
    states: [255]?W.State = [_] ?W.State { null } ** 255,

    pub fn parse(lines: *Iter) !TilePallet {
        var self: TilePallet = .{};

        try requireNext(lines, "NOUNS");
        while (lines.next()) |line| {
            if (std.mem.eql(u8, line, "STATES")) {
                break;
            }

            const c = line[0];
            const name = line[2..];
            const value = enumFromTagName(W.Noun, name) orelse return ParseErr;
            self.nouns[@intCast(c)] = value;
        }

        while (lines.next()) |line| {
            if (line.len == 0) {
                break;
            }

            const c = line[0];
            const name = line[2..];
            const value = enumFromTagName(W.State, name) orelse return ParseErr;
            self.states[@intCast(c)] = value;
        }
        
        return self;
    }
};

pub fn readLevelMap(self: *W.Level, lines: *Iter, pallet: TilePallet) !void {
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
                const noun = pallet.nouns[index] orelse return ParseErr;
                try self.addEntity(pos, .{ .Object=noun });
            } else {
                if (pallet.nouns[c]) |noun| {
                    try self.addEntity(pos, .{ .Noun=noun });
                } else if (pallet.states[c]) |state| {
                    try self.addEntity(pos, .{ .State=state });
                } else if (c == '=') {
                    try self.addEntity(pos, .{ .Connect=.Is});
                } else if (c == '+') {
                    try self.addEntity(pos,  .{ .Connect=.And});
                } else {
                    return ParseErr;
                }
            }
        }
    }

    self.size = pos;
    self.updateRules();
} 

pub fn loadLevel(data: [] const u8, alloc: std.mem.Allocator) !W.Level {
    var self = W.Level.init(alloc, .{ 0, 0 });
    var lines = std.mem.splitScalar(u8, data, '\n');
    try requireCurrentVersion(&lines);
    
    const pallet = try TilePallet.parse(&lines);
    try requireNext(&lines, "MAP");
    try readLevelMap(&self, &lines, pallet);
    return self;
}


// TODO: package these into a convient parser struct so the TestIter code has less awkwardly importing these. 

pub fn readInt(lines: *Iter) !usize {
    const intStr = lines.next() orelse return ParseErr;
    return std.fmt.parseInt(u32, intStr, 10) catch return ParseErr;
}

pub fn requireCurrentVersion(lines: *Iter) !void {
    if (try readInt(lines) != VERSION) {
        return ParseErr;
    }
}

pub fn requireNext(lines: *Iter, marker: []const u8) !void {
    const found = lines.next() orelse return ParseErr;
    const valid = std.mem.eql(u8, found, marker);
    if (!valid) {
        logErr("Expected '{s}' but found '{s}'\n", .{ marker, found, });
        return ParseErr;
    }
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
