const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const Allocator = mem.Allocator;

/// Singly-Linked List
pub fn SLList(comptime T: type) type {
    return struct {
        const Self = @This();
        const Node = struct {
            x: T,
            next: ?*Node,
        };
        head: ?*Node,
        tail: ?*Node,
        size: usize,
        allocator: Allocator,

        pub fn init(allocator: Allocator) Self {
            return Self{
                .head = null,
                .tail = null,
                .size = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: Self) void {
            var node = self.head;
            while (node) |n| {
                self.allocator.destroy(n);
                node = n.next;
            }
        }

        pub fn push(self: *Self, x: T) Allocator.Error!void {
            const node = try self.allocator.create(Node);
            node.* = .{ .x = x, .next = self.head };
            self.head = node;
            self.size += 1;
            if (self.size == 1) {
                self.tail = self.head;
            }
        }

        pub fn pop(self: *Self) ?T {
            const node = self.head orelse return null;
            const x = node.x;
            defer self.allocator.destroy(node);
            self.head = node.next;
            self.size -= 1;
            if (self.size == 0) {
                self.tail = null;
            }
            return x;
        }

        pub fn add(self: *Self, x: T) Allocator.Error!void {
            const node = try self.allocator.create(Node);
            node.* = .{ .x = x, .next = null };
            if (self.tail) |t| {
                t.next = node;
                self.tail.?.next = node;
            } else {
                self.head = node;
            }
            self.tail = node;
            self.size += 1;
        }

        pub fn remove(self: *Self) ?T {
            return self.pop();
        }

        fn check_index(self: Self, i: usize) void {
            if (i < 0 or i >= self.size) {
                @panic("index out of bounds");
            }
        }

        pub fn get(self: Self, i: usize) T {
            self.check_index(i);
            var node = self.head;
            for (0..i) |_| {
                node = node.?.next;
            }
            return node.?.x;
        }

        pub const Iterator = struct {
            current: ?*Node,
            pub fn next(it: *Iterator) ?T {
                if (it.current) |cur| {
                    it.current = cur.next;
                    return cur.x;
                } else {
                    return null;
                }
            }
        };

        pub fn iterate(self: Self) Iterator {
            return Iterator{ .current = self.head };
        }
    };
}

test "push/pop" {
    var list = SLList(i32).init(testing.allocator);
    defer list.deinit();
    try list.push(3); // [1]
    try list.push(2); // [1, 3]
    try list.push(1); // [1, 2, 3]
    for (0.., [_]i32{ 1, 2, 3 }) |i, expected| {
        try testing.expectEqual(expected, list.get(i));
    }
    try testing.expectEqual(1, list.pop().?);
    try testing.expectEqual(2, list.pop().?);
    try testing.expectEqual(3, list.pop().?);
    try testing.expectEqual(null, list.pop());
}

test "add/remove" {
    var list = SLList(i32).init(testing.allocator);
    defer list.deinit();
    try list.add(1); // [1]
    try list.add(2); // [1, 3]
    try list.add(3); // [1, 2, 3]
    for (0.., [_]i32{ 1, 2, 3 }) |i, expected| {
        try testing.expectEqual(expected, list.get(i));
    }
    try testing.expectEqual(1, list.remove().?);
    try testing.expectEqual(2, list.remove().?);
    try testing.expectEqual(3, list.remove().?);
    try testing.expectEqual(null, list.remove());
}
