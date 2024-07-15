const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const Allocator = mem.Allocator;

/// Doubly-Linked List
pub fn DLList(comptime T: type) type {
    return struct {
        const Self = @This();
        const Node = struct {
            x: T,
            next: *Node,
            prev: *Node,
        };
        sentinel: *Node,
        size: usize,
        allocator: Allocator,

        pub fn init(allocator: Allocator) Allocator.Error!Self {
            const sentinel = try allocator.create(Node);
            errdefer allocator.destroy(sentinel);
            sentinel.* = Node{
                .x = undefined,
                .next = sentinel,
                .prev = sentinel,
            };
            return Self{
                .sentinel = sentinel,
                .size = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            var node = self.sentinel.next;
            while (node != self.sentinel) {
                const target_node = node;
                node = node.next;
                self.allocator.destroy(target_node);
            }
            self.allocator.destroy(self.sentinel);
        }

        fn getNode(self: *Self, i: usize) *Node {
            if (i < self.size / 2) {
                var node = self.sentinel.next;
                for (0..i) |_| {
                    node = node.next;
                }
                return node;
            } else {
                var node = self.sentinel;
                for (i..self.size) |_| {
                    node = node.prev;
                }
                return node;
            }
        }

        fn addBefore(self: *Self, node: *Node, x: T) Allocator.Error!*Node {
            // [node.prev, node] to [node.prev, new_node, node]
            const new_node = try self.allocator.create(Node);
            errdefer self.allocator.destroy(new_node);
            new_node.* = .{ .x = x, .next = node, .prev = node.prev };
            new_node.next.prev = new_node;
            new_node.prev.next = new_node;
            self.size += 1;
            return new_node;
        }

        fn removeNode(self: *Self, node: *Node) void {
            // [node.prev, node, node.next] to [node.prev, node.next]
            node.prev.next = node.next;
            node.next.prev = node.prev;
            self.allocator.destroy(node);
            self.size -= 1;
        }

        pub fn remove(self: *Self, i: usize) T {
            const node = self.getNode(i);
            const x = node.x;
            self.removeNode(node);
            return x;
        }

        pub fn add(self: *Self, i: usize, x: T) Allocator.Error!void {
            _ = try self.addBefore(self.getNode(i), x);
        }

        pub fn get(self: *Self, i: usize) T {
            return self.getNode(i).x;
        }

        pub fn set(self: *Self, i: usize, value: T) T {
            var node = self.getNode(i);
            const x = node.x;
            node.x = value;
            return x;
        }
    };
}

test "list operations" {
    var list = try DLList(i32).init(testing.allocator);
    defer list.deinit();
    try list.add(0, 1); // [1]
    try list.add(1, 2); // [1, 3]
    try list.add(2, 3); // [1, 2, 3]
    for (0.., [_]i32{ 1, 2, 3 }) |i, expected| {
        try testing.expectEqual(expected, list.get(i));
    }
    try testing.expectEqual(2, list.remove(1)); // [1, 3]
    try list.add(2, 4); // [1, 3, 4]
    try list.add(2, 5); // [1, 3, 5, 4]
    try testing.expectEqual(5, list.remove(2)); // [1, 3, 4]
    try list.add(1, 6); // [1, 6, 3, 4]
    try list.add(3, 7); // [1, 6, 3, 7, 4]
    try list.add(0, 8); // [8, 1, 6, 3, 7, 4]
    for (0.., [_]i32{ 8, 1, 6, 3, 7, 4 }) |i, expected| {
        try testing.expectEqual(expected, list.get(i));
    }
    try testing.expectEqual(3, list.remove(3)); // [8, 1, 6, 7, 4]
    try testing.expectEqual(7, list.remove(3)); // [8, 1, 6, 4]
    try testing.expectEqual(6, list.remove(2)); // [8, 1, 4]
    for (0.., [_]i32{ 8, 1, 4 }) |i, expected| {
        try testing.expectEqual(expected, list.get(i));
    }
}
