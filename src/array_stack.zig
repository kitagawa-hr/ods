const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const Allocator = mem.Allocator;

/// ArrayStack (equivalent to FastArrayStack in the book)
/// Reference: [C Implementation](https://github.com/patmorin/ods/tree/master/c)
pub fn ArrayStack(comptime T: type) type {
    return struct {
        const Self = @This();
        a: []T,
        size: usize,
        allocator: Allocator,

        pub fn init(allocator: Allocator) Allocator.Error!Self {
            return Self{
                .a = try allocator.alloc(T, 1),
                .size = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: Self) void {
            self.allocator.free(self.a);
        }

        fn resize(self: *Self) Allocator.Error!void {
            const new_length = if (self.size > 0) self.size * 2 else 1;
            self.a = try self.allocator.realloc(self.a, new_length);
        }

        pub fn add(self: *Self, i: usize, value: T) Allocator.Error!void {
            if (self.size + 1 >= self.a.len) {
                try self.resize();
            }
            mem.copyBackwards(T, self.a[i + 1 .. self.size + 1], self.a[i..self.size]);
            self.a[i] = value;
            self.size += 1;
        }

        pub fn remove(self: *Self, i: usize) Allocator.Error!T {
            if (self.a.len > 3 * self.size) {
                try self.resize();
            }
            const x = self.a[i];
            mem.copyForwards(T, self.a[i .. self.size - 1], self.a[i + 1 .. self.size]);
            self.size -= 1;
            return x;
        }

        fn check_index(self: Self, i: usize) void {
            if (i < 0 or i >= self.size) {
                @panic("index out of bounds");
            }
        }

        pub fn get(self: Self, i: usize) T {
            self.check_index(i);
            return self.a[i];
        }

        pub fn set(self: *Self, i: usize, value: T) void {
            self.check_index(i);
            self.a[i] = value;
        }

        pub fn as_slice(self: *Self) []T {
            return self.a[0..self.size];
        }
    };
}

test "add and remove" {
    var stack = ArrayStack(i32).init(testing.allocator) catch @panic("panic");
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

test "large data using std.ArrayList" {
    var std_list = std.ArrayList(usize).init(testing.allocator);
    var stack = try ArrayStack(usize).init(testing.allocator);
    defer std_list.deinit();
    defer stack.deinit();
    // add last
    for (0..500) |i| {
        try std_list.append(i);
        try stack.add(i, i);
    }
    // add first
    for (0..500) |i| {
        try std_list.insert(0, i);
        try stack.add(0, i);
    }
    // add random
    for (0..30) |i| {
        try std_list.insert(i * i, i * i);
        try stack.add(i * i, i * i);
    }
    // set
    for (300..800) |i| {
        std_list.items[i] = i;
        stack.set(i, i);
    }
    // remove random
    for (0..30) |i| {
        try testing.expectEqual(std_list.orderedRemove(i * i - i), try stack.remove(i * i - i));
    }
    // assert all elements
    try testing.expectEqual(std_list.items.len, stack.size);
    for (0..std_list.items.len) |i| {
        try testing.expectEqual(std_list.items[i], stack.get(i));
    }
}
