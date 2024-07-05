const std = @import("std");
const Allocator = std.mem.Allocator;
const array_stack = @import("./array_stack.zig");
const ArrayStack = array_stack.ArrayStack;
const testing = std.testing;

/// A double-ended queue implemented using two array stacks.
///
/// Example:
///     front          back
///  5 4 3 2 1 0     0 1 2 3 4 5
/// | | |a|b|c|d|   |e|f|g| | | |
///
pub fn DualArrayDeque(comptime T: type) type {
    return struct {
        const Self = @This();
        front: ArrayStack(T),
        back: ArrayStack(T),
        allocator: Allocator,

        pub fn init(allocator: Allocator) Allocator.Error!Self {
            return Self{
                .front = try ArrayStack(T).init(allocator),
                .back = try ArrayStack(T).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.front.deinit();
            self.back.deinit();
        }

        fn size(self: *Self) usize {
            return self.front.size + self.back.size;
        }

        fn get(self: *Self, i: usize) T {
            if (i < self.front.size) {
                return self.front.get(self.front.size - i - 1);
            } else {
                return self.back.get(i - self.front.size);
            }
        }

        pub fn set(self: *Self, i: usize, value: T) void {
            if (i < self.front.size) {
                self.front.set(self.front.size - i - 1, value);
            } else {
                self.back.set(i - self.front.size, value);
            }
        }

        pub fn add(self: *Self, i: usize, value: T) Allocator.Error!void {
            if (i < self.front.size) {
                try self.front.add(self.front.size - i, value);
            } else {
                try self.back.add(i - self.front.size, value);
            }
            try self.balance();
        }

        pub fn remove(self: *Self, i: usize) Allocator.Error!T {
            if (i < self.front.size) {
                return try self.front.remove(self.front.size - i - 1);
            } else {
                return try self.back.remove(i - self.front.size);
            }
            try self.balance();
        }

        fn balance(self: *Self) Allocator.Error!void {
            if (self.front.size * 3 < self.back.size or self.back.size * 3 < self.front.size) {
                //  5 4 3 2 1 0     0 1 2 3 4 5
                // | | |a|b|c|d|   |e| | | | | |
                // | | | | |a|b|   |c|d|e| | | |
                const nf = self.size() / 2;
                const nb = self.size() - nf;
                var new_af = try self.allocator.alloc(T, 2 * nf);
                var new_ab = try self.allocator.alloc(T, 2 * nb);
                for (0..nf) |i| {
                    new_af[nf - i - 1] = self.get(i);
                }
                for (0..nb) |i| {
                    new_ab[i] = self.get(nf + i);
                }
                self.front.deinit();
                self.back.deinit();
                self.front = ArrayStack(T){
                    .a = new_af,
                    .size = nf,
                    .allocator = self.allocator,
                };
                self.back = ArrayStack(T){
                    .a = new_ab,
                    .size = nb,
                    .allocator = self.allocator,
                };
            }
        }
    };
}

test "add and remove" {
    var deque = DualArrayDeque(i32).init(testing.allocator) catch @panic("panic");
    defer deque.deinit();
    try deque.add(0, 1); // [1]
    try deque.add(1, 2); // [1, 3]
    try deque.add(2, 3); // [1, 2, 3]
    for (0.., [_]i32{ 1, 2, 3 }) |i, expected| {
        try testing.expectEqual(expected, deque.get(i));
    }
    try testing.expectEqual(2, try deque.remove(1)); // [1, 3]
    try deque.add(2, 4); // [1, 3, 4]
    try deque.add(2, 5); // [1, 3, 5, 4]
    try testing.expectEqual(5, try deque.remove(2)); // [1, 3, 4]
    try deque.add(1, 6); // [1, 6, 3, 4]
    try deque.add(3, 7); // [1, 6, 3, 7, 4]
    try deque.add(0, 8); // [8, 1, 6, 3, 7, 4]
    for (0.., [_]i32{ 8, 1, 6, 3, 7, 4 }) |i, expected| {
        try testing.expectEqual(expected, deque.get(i));
    }
    try testing.expectEqual(3, try deque.remove(3)); // [8, 1, 6, 7, 4]
    try testing.expectEqual(7, try deque.remove(3)); // [8, 1, 6, 4]
    try testing.expectEqual(6, try deque.remove(2)); // [8, 1, 4]
    for (0.., [_]i32{ 8, 1, 4 }) |i, expected| {
        try testing.expectEqual(expected, deque.get(i));
    }
}
