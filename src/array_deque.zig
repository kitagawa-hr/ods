const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const Allocator = mem.Allocator;

/// Double-ended queue implemented with a circular array.
///
/// Example:
///  size=5, head=8, a.len=10, tail=3
///  0 1 2 3 4 5 6 7 8 9
/// |c|d|e| | | | | |a|b|
///        ^tail     ^head
///  add(x) insert x at
///  remove() remove element at head
///
pub fn ArrayDeque(comptime T: type) type {
    return struct {
        const Self = @This();
        a: []T,
        head: usize,
        size: usize,
        allocator: Allocator,

        pub fn init(allocator: mem.Allocator) Allocator.Error!Self {
            return Self{
                .a = try allocator.alloc(T, 1),
                .head = 0,
                .size = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: Self) void {
            self.allocator.free(self.a);
        }

        fn head_index(self: Self) usize {
            return self.head % self.a.len;
        }

        fn tail_index(self: Self) usize {
            return (self.head + self.size) % self.a.len;
        }

        fn resize(self: *Self) Allocator.Error!void {
            // |d|e|f|a|b|c|
            // to
            // |a|b|c|d|e|f| | | | | | |
            const new_length = if (self.size > 0) self.size * 2 else 1;
            const new_a = try self.allocator.alloc(T, new_length);
            for (0..self.size) |i| {
                new_a[i] = self.a[(self.head_index() + i) % self.a.len];
            }
            self.allocator.free(self.a);
            self.a = new_a;
            self.head = 0;
        }

        fn check_index(self: Self, i: usize) void {
            if (i < 0 or i >= self.size) {
                @panic("index out of bounds");
            }
        }

        pub fn get(self: Self, i: usize) T {
            self.check_index(i);
            return self.a[(self.head + i) % self.a.len];
        }

        pub fn set(self: *Self, i: usize, value: T) void {
            self.check_index(i);
            self.a[(self.head + i) % self.a.len] = value;
        }

        // shift [l, r) to left
        fn shift_left(self: *Self, l: usize, r: usize) void {
            if (l == r) {
                return;
            }
            if (l == 0) {
                self.a[self.a.len - 1] = self.a[0];
                mem.copyForwards(T, self.a[0 .. r - 1], self.a[1..r]);
                return;
            }
            if (l < r) {
                // | | |l|*|*|*|r| | |
                mem.copyForwards(T, self.a[l - 1 .. r - 1], self.a[l..r]);
            } else {
                // |*|*|r| | | |l|*|*|
                self.shift_left(l, self.a.len);
                self.shift_left(0, r);
            }
        }

        // shift [l, r) to right
        fn shift_right(self: *Self, l: usize, r: usize) void {
            if (l == r) {
                return;
            }
            if (l < r) {
                // | | |l|*|*|*|r| | |
                mem.copyBackwards(T, self.a[l + 1 .. r + 1], self.a[l..r]);
            } else {
                // |*|*|r| | | |l|*|*|
                self.shift_right(0, r);
                self.a[0] = self.a[self.a.len - 1];
                self.shift_right(l, self.a.len - 1);
            }
        }

        pub fn add(self: *Self, i: usize, value: T) Allocator.Error!void {
            if (self.size + 1 >= self.a.len) {
                try self.resize();
            }
            if (i < self.size / 2) {
                // shift a[head..head+i] to left
                self.shift_left(self.head_index(), (self.head + i) % self.a.len);
                self.head = (self.head + self.a.len - 1) % self.a.len;
            } else {
                // shift a[head+i..tail] to right
                self.shift_right((self.head + i) % self.a.len, self.tail_index());
            }
            self.a[(self.head + i) % self.a.len] = value;
            self.size += 1;
        }

        pub fn remove(self: *Self, i: usize) Allocator.Error!T {
            const x = self.get(i);
            if (self.a.len >= 3 * self.size) {
                try self.resize();
            }
            if (i < self.size / 2) {
                // shift a[head..head+i] to right
                self.shift_right(self.head_index(), (self.head + i) % self.a.len);
                self.head += 1;
            } else {
                // shift a[head+i+1..tail] to left
                self.shift_left((self.head + i + 1) % self.a.len, self.tail_index());
            }
            self.size -= 1;
            return x;
        }
    };
}

test "add and remove" {
    var deque = ArrayDeque(i32).init(testing.allocator) catch @panic("panic");
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
