const std = @import("std");
const W = @import("../world.zig");
const T = @import("../serde/test_cases.zig");

pub const TestIter = struct {
    arena: std.heap.ArenaAllocator,
    cases: []T.TestCase = undefined,
    testIndex: usize = 0,
    actionIndex: usize = 0,
    frames: usize = 0,
    passed: usize = 0,
    failed: usize = 0,
    speed: usize = 1,

    // No init because want the struct to be on the stack where it lives so allocator pointers to arena stays valid.
    pub fn load(self: *TestIter) !void {
        // TODO: if I cared about memory, I wouldn't load them all up front. just clear the level and update as needed. 
        //       i also don't like that my only way to read the test data format is coupled with loading levels from the filesystem. 
        //       but it makes a lot of sense for the mini tests where the levels are in the same file
        self.cases = try T.loadTests(self.arena.allocator());
    }

    pub fn getLevel(self: *TestIter) *W.Level {
        return &self.cases[self.testIndex].level;
    }

    pub fn tick(self: *TestIter) bool {
        self.frames += 1;
        if (self.speed != 0 and self.frames % self.speed == 0) {
            return self.advance();
        }
        return true;
    }

    fn advance(self: *TestIter) bool {
        const t = &self.cases[self.testIndex];
        if (self.actionIndex >= t.actions.len) {
            if (self.getLevel().state != t.endState) {
                std.debug.print("\nFAIL test {} Expected {s} but got {s}.\n", .{ self.testIndex, @tagName(t.endState), @tagName(self.getLevel().state) });
                self.failed += 1;
            } else {
                self.passed += 1;
            }
            self.actionIndex = 0;
            self.testIndex += 1;
            if (self.testIndex >= self.cases.len) {
                if (!@import("builtin").is_test) {
                    std.debug.print("Tests Finished. Passed {}/{}.\n", .{ self.passed, self.cases.len });
                }
                return false;
            }
        } else {
            const a = t.actions[self.actionIndex];
            self.getLevel().handleInput(a) catch |err| {
                std.debug.print("\nFailed to play test input {} {}.\n", .{ a, err, });
                self.actionIndex = t.actions.len;  // Skip to the end so it fails. TODO: i guess this is wrong if it expected None cause that's probably the current state. 
            };
            self.actionIndex += 1;
        }

        return true;
    }

    pub fn deinit(self: TestIter) void {
        self.arena.deinit();
    }
};
