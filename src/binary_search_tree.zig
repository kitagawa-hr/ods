const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const Allocator = mem.Allocator;

pub fn BinarySearchTree(comptime T: type) type {
    return struct {
        const Self = @This();
        size: usize,
        root: ?*Node,
        allocator: Allocator,

        const Node = struct {
            value: T,
            parent: ?*Node,
            left: ?*Node,
            right: ?*Node,
        };

        pub fn init(allocator: Allocator) !Self {
            return Self{
                .size = 0,
                .root = null,
                .allocator = allocator,
            };
        }

        fn freeNodes(self: Self, node: ?*Node) void {
            if (node) |u| {
                self.freeNodes(u.left);
                self.freeNodes(u.right);
                self.allocator.destroy(u);
            }
        }

        pub fn deinit(self: Self) void {
            self.freeNodes(self.root);
        }

        fn findNode(self: Self, x: T, node: *Node) *Node {
            if (node.value < x and node.right != null) {
                return self.findNode(x, node.right.?);
            }
            if (node.value > x and node.left != null) {
                return self.findNode(x, node.left.?);
            }
            return node;
        }

        pub fn find(self: Self, x: T) ?T {
            if (self.root) |r| {
                const node = self.findNode(x, r);
                if (node.value == x) {
                    return node.value;
                }
            }
            return null;
        }

        pub fn add(self: *Self, x: T) Allocator.Error!bool {
            if (self.root) |r| {
                const node = self.findNode(x, r);
                if (node.value == x) {
                    return false;
                }
                const new_node = try self.allocator.create(Node);
                new_node.* = .{
                    .value = x,
                    .parent = node,
                    .left = null,
                    .right = null,
                };
                if (node.value < x) {
                    node.right = new_node;
                } else {
                    node.left = new_node;
                }
                self.size += 1;
                return true;
            }
            const new_node = try self.allocator.create(Node);
            new_node.* = .{
                .value = x,
                .parent = null,
                .left = null,
                .right = null,
            };
            self.root = new_node;
            self.size += 1;
            return true;
        }

        fn getSup(node: *Node) *Node {
            var u = node;
            while (u.right) |r| {
                u = r;
            }
            return u;
        }

        fn getInf(node: *Node) *Node {
            var u = node;
            while (u.left) |r| {
                u = r;
            }
            return u;
        }

        /// Remove node and splice node.child and node.parent
        fn splice(self: *Self, node: *Node) void {
            const child = if (node.left != null) node.left else node.right;
            if (node.parent) |p| {
                if (p.left == node) {
                    p.left = child;
                } else {
                    p.right = child;
                }
            } else {
                self.root = child;
            }
            if (child) |c| {
                c.parent = node.parent;
            }
            self.allocator.destroy(node);
            self.size -= 1;
        }

        fn removeNode(self: *Self, node: *Node) void {
            if (node.left == null or node.right == null) {
                self.splice(node);
            } else {
                const inf_node = getInf(node.right.?);
                node.value = inf_node.value;
                self.splice(inf_node);
            }
        }

        pub fn remove(self: *Self, x: T) ?T {
            if (self.root) |r| {
                const removed_node = self.findNode(x, r);
                if (removed_node.value != x) {
                    return null;
                }
                const y = removed_node.value;
                self.removeNode(removed_node);
                return y;
            }
            return null;
        }
    };
}

test "uset operations" {
    var set = try BinarySearchTree(i32).init(testing.allocator);
    defer set.deinit();
    // add
    try testing.expect(try set.add(10));
    try testing.expect(try set.add(100));
    try testing.expect(try set.add(1000));
    try testing.expect(try set.add(10000));
    try testing.expect(try set.add(100000));
    try testing.expect(try set.add(1000000));
    try testing.expect(try set.add(10000000));
    try testing.expect(try set.add(100000000));
    try testing.expect(try set.add(1000000000));
    try testing.expectEqual(false, try set.add(10));
    try testing.expectEqual(false, try set.add(100));
    try testing.expectEqual(false, try set.add(1000));
    try testing.expectEqual(false, try set.add(10000));
    // find
    try testing.expectEqual(9, set.size);
    try testing.expectEqual(10, set.find(10));
    try testing.expectEqual(10000, set.find(10000));
    try testing.expectEqual(null, set.find(1));

    // remove
    try testing.expectEqual(10, set.remove(10));
    try testing.expectEqual(100, set.remove(100));
    try testing.expectEqual(1000, set.remove(1000));
    try testing.expectEqual(10000, set.remove(10000));
    try testing.expectEqual(null, set.remove(10));
    try testing.expectEqual(null, set.remove(100));
    try testing.expectEqual(null, set.remove(1000));
    try testing.expectEqual(null, set.remove(10000));
    try testing.expectEqual(null, set.remove(8));
    try testing.expectEqual(5, set.size);

    try testing.expectEqual(null, set.find(10));
    try testing.expectEqual(null, set.find(100));
    try testing.expectEqual(null, set.find(1000));
    try testing.expectEqual(null, set.find(10000));

    try testing.expectEqual(100000, set.find(100000));
    try testing.expectEqual(1000000, set.find(1000000));
    try testing.expectEqual(10000000, set.find(10000000));
    try testing.expectEqual(100000000, set.find(100000000));
}
