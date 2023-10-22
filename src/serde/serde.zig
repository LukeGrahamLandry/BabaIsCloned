/// Re-exports the convinent serialization functions. 
// TODO: I don't really like this. The logic was it lets me see what api is actually exposed 
//       since zig doesn't have package scoped functions, so if I'm careful to only import through this, I get that information. 
//       Also I don't like importing from many different files in main since zig doesn't have a nice ide 
//       that hides the noise and auto-imports. Maybe you're supposed to just put it at the bottom. 

pub const loadLevel = @import("save.zig").loadLevel;
pub const saveLevel = @import("save.zig").saveLevel;

const o = @import("official.zig");
pub const loadLevelOfficial = o.loadLevel;
pub fn getBaseTileset() ?o.TileSet {
    // TODO: try load. pass in path? 
    return o.tileSet;
}
pub const TileSet = o.TileSet;

pub const TestCase = @import("test_cases.zig").TestCase;
pub const loadTests = @import("test_cases.zig").loadTests;
pub const saveTestRoute = @import("test_cases.zig").saveTestRoute;
