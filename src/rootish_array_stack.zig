const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayStack = @import("array_stack.zig").ArrayStack;

/// A Space-Efficient ArrayStack
///
///  0    1 2    3 4 5    6 7 8 9
/// |a|  |b|c|  |d|e|f|  |g|h| | |
///
pub fn RootishArrayStack(comptime T: type) type {
    return struct {
        const Self = @This();
        blocks: ArrayStack([]T),
        size: usize,
        allocator: Allocator,

        pub fn init(allocator: Allocator) Allocator.Error!Self {
            return Self{
                .blocks = try ArrayStack([]T).init(allocator),
                .size = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: Self) void {
            for (0..self.blocks.size) |i| {
                self.allocator.free(self.blocks.get(i));
            }
            self.blocks.deinit();
        }

        fn i2b(i: usize) usize {
            const j: f32 = @floatFromInt(i);
            const b: usize = @intFromFloat(@ceil((@sqrt(8.0 * j + 9.0) - 3.0) / 2.0));
            return b;
        }

        fn check_index(self: Self, i: usize) void {
            if (i < 0 or i >= self.size) {
                @panic("index out of bounds");
            }
        }

        pub fn get(self: Self, i: usize) T {
            self.check_index(i);
            const b = i2b(i);
            const j = i - b * (b + 1) / 2;
            return self.blocks.get(b)[j];
        }

        pub fn set(self: *Self, i: usize, value: T) void {
            self.check_index(i);
            const b = i2b(i);
            const j = i - b * (b + 1) / 2;
            self.blocks.get(b)[j] = value;
        }

        fn grow(self: *Self) Allocator.Error!void {
            try self.blocks.add(
                self.blocks.size,
                try self.allocator.alloc(T, self.blocks.size + 1),
            );
        }

        fn shrink(self: *Self) Allocator.Error!void {
            var r = self.blocks.size;
            while (r > 0 and (r - 2) * (r - 1) / 2 >= self.size) {
                self.allocator.free(self.blocks.get(self.blocks.size - 1));
                r -= 1;
            }
        }

        pub fn add(self: *Self, i: usize, value: T) Allocator.Error!void {
            const bs = self.blocks.size;
            if (bs * (bs + 1) / 2 < self.size + 1) {
                try self.grow();
            }
            self.size += 1;
            // shift [i+1..] to right
            var j = self.size - 1;
            while (i < j) {
                self.set(j, self.get(j - 1));
                j -= 1;
            }
            self.set(i, value);
        }

        pub fn remove(self: *Self, i: usize) Allocator.Error!T {
            const x = self.get(i);
            // shift [i..] to left
            for (i..self.size - 1) |j| {
                self.set(j, self.get(j + 1));
            }
            self.size -= 1;
            const bs = self.blocks.size;
            if ((bs - 2) * (bs - 1) / 2 >= self.size) {
                try self.shrink();
            }
            return x;
        }
    };
}

test "add and remove" {
    var stack = RootishArrayStack(i32).init(testing.allocator) catch @panic("panic");
    defer stack.deinit();
    try stack.add(0, 1); // [1]
    try stack.add(1, 2); // [1, 3]
    try stack.add(2, 3); // [1, 2, 3]
    for (0.., [_]i32{ 1, 2, 3 }) |i, expected| {
        try testing.expectEqual(expected, stack.get(i));
    }
    try testing.expectEqual(2, try stack.remove(1)); // [1, 3]
    try stack.add(2, 4); // [1, 3, 4]
    try stack.add(2, 5); // [1, 3, 5, 4]
    try testing.expectEqual(5, try stack.remove(2)); // [1, 3, 4]
    try stack.add(1, 6); // [1, 6, 3, 4]
    try stack.add(3, 7); // [1, 6, 3, 7, 4]
    try stack.add(0, 8); // [8, 1, 6, 3, 7, 4]
    for (0.., [_]i32{ 8, 1, 6, 3, 7, 4 }) |i, expected| {
        try testing.expectEqual(expected, stack.get(i));
    }
    try testing.expectEqual(3, try stack.remove(3)); // [8, 1, 6, 7, 4]
    try testing.expectEqual(7, try stack.remove(3)); // [8, 1, 6, 4]
    try testing.expectEqual(6, try stack.remove(2)); // [8, 1, 4]
    for (0.., [_]i32{ 8, 1, 4 }) |i, expected| {
        try testing.expectEqual(expected, stack.get(i));
    }
}
