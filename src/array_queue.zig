const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const Allocator = mem.Allocator;

/// FIFO queue implemented with a circular array.
///
/// Example:
///  size=5, tail=13, a.len=10, head=(13-5)%10=8
///  0 1 2 3 4 5 6 7 8 9
/// |c|d|e| | | | | |a|b|
///        ^tail     ^head
///  add(x) insert x at
///  remove() remove element at head
///
fn ArrayQueue(comptime T: type) type {
    return struct {
        const Self = @This();
        a: []T,
        tail: usize,
        size: usize,
        allocator: Allocator,

        pub fn init(allocator: mem.Allocator) Allocator.Error!Self {
            return Self{
                .a = try allocator.alloc(T, 1),
                .tail = 0,
                .size = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: Self) void {
            self.allocator.free(self.a);
        }

        fn head_index(self: Self) usize {
            return (self.tail + self.a.len - self.size) % self.a.len;
        }

        fn tail_index(self: Self) usize {
            return self.tail % self.a.len;
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
            self.tail = self.size;
        }

        pub fn add(self: *Self, value: T) Allocator.Error!void {
            if (self.size + 1 >= self.a.len) {
                try self.resize();
            }
            self.a[self.tail_index()] = value;
            self.size += 1;
            self.tail += 1;
        }

        pub fn remove(self: *Self) Allocator.Error!T {
            const x = self.a[self.head_index()];
            self.size -= 1;
            if (self.a.len >= 3 * self.size) {
                try self.resize();
            }
            return x;
        }
    };
}

test "add and remove" {
    var queue = ArrayQueue(i32).init(testing.allocator) catch @panic("panic");
    defer queue.deinit();
    try queue.add(1);
    try queue.add(2);
    try queue.add(3);
    try testing.expectEqual(1, try queue.remove());
    try queue.add(4);
    try queue.add(5);
    try testing.expectEqual(2, try queue.remove());
    try queue.add(6);
    try queue.add(7);
    try queue.add(8);
    try testing.expectEqual(3, try queue.remove());
    try testing.expectEqual(4, try queue.remove());
    try testing.expectEqual(5, try queue.remove());
    try testing.expectEqual(6, try queue.remove());
}
