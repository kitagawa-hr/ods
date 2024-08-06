const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const Allocator = mem.Allocator;

/// Sorted Set implemented as a skiplist.
pub fn SkiplistSSet(comptime T: type, comptime max_height: u8) type {
    return struct {
        const Self = @This();
        const Node = struct {
            value: T,
            height: u8,
            nexts: []?*Node,
        };
        sentinel: *Node,
        size: usize,
        allocator: Allocator,

        pub fn init(allocator: Allocator) Allocator.Error!Self {
            return Self{
                .sentinel = try allocNode(allocator, max_height),
                .size = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: Self) void {
            var node = self.sentinel.nexts[0];
            while (node != null) {
                const target_node = node;
                node = node.?.nexts[0];
                self.freeNode(target_node.?);
            }
            self.freeNode(self.sentinel);
        }

        fn allocNode(allocator: Allocator, height: u8) Allocator.Error!*Node {
            const node = try allocator.create(Node);
            var nexts = try allocator.alloc(?*Node, height);
            for (0..height) |y| {
                nexts[y] = null;
            }
            node.* = .{
                .value = undefined,
                .height = height,
                .nexts = nexts,
            };
            return node;
        }

        fn freeNode(self: Self, node: *Node) void {
            self.allocator.free(node.nexts);
            self.allocator.destroy(node);
        }

        /// Find the smallest node of which value >= x.
        ///
        /// 3|*|-----|*|
        /// 2|*|-----|*|-|*|
        /// 1|*|-|*|-|*|-|*|
        /// 0|*|-|*|-|*|-|*|
        ///   s   0   1   2
        fn findPredNode(self: Self, x: T) *Node {
            var node: *Node = self.sentinel;
            var height = max_height;
            while (height > 0) : (height -= 1) {
                while (node.nexts[height - 1]) |u| {
                    if (u.value >= x) {
                        break;
                    }
                    node = u;
                }
            }
            return node;
        }

        pub fn find(self: Self, x: T) ?T {
            const node = self.findPredNode(x).nexts[0] orelse return null;
            return node.value;
        }

        fn pickHeight() !u8 {
            var seed: u64 = undefined;
            try std.posix.getrandom(std.mem.asBytes(&seed));
            var prng = std.rand.DefaultPrng.init(seed);
            const rand = prng.random();
            return rand.intRangeAtMost(u8, 1, max_height);
        }

        pub fn add(self: *Self, x: T) !bool {
            var node = self.sentinel;
            var height = max_height;
            var nodes_before: [max_height]*Node = undefined;
            while (height > 0) : (height -= 1) {
                while (node.nexts[height - 1]) |next_node| {
                    if (next_node.value > x) {
                        break;
                    }
                    if (next_node.value == x) {
                        return false;
                    }
                    node = next_node;
                }
                nodes_before[height - 1] = node;
            }
            const new_height = try pickHeight();
            const new_node = try allocNode(self.allocator, new_height);
            new_node.value = x;
            for (0..new_height) |h| {
                new_node.nexts[h] = nodes_before[h].nexts[h];
                nodes_before[h].nexts[h] = new_node;
            }
            self.size += 1;
            return true;
        }

        pub fn remove(self: *Self, x: T) !bool {
            var node = self.sentinel;
            var height = max_height;
            var removedNode: ?*Node = null;
            var nodes_before: [max_height]*Node = undefined;
            while (height > 0) : (height -= 1) {
                while (node.nexts[height - 1]) |next_node| {
                    if (next_node.value > x) {
                        break;
                    }
                    if (next_node.value == x) {
                        removedNode = next_node;
                        node.nexts[height - 1] = next_node.nexts[height - 1];
                        break;
                    }
                    node = next_node;
                }
                nodes_before[height - 1] = node;
            }
            if (removedNode) |u| {
                self.freeNode(u);
                self.size -= 1;
                return true;
            }
            return false;
        }

        pub fn get(self: Self, i: usize) T {
            std.debug.assert(0 <= i and i < self.size);
            var node = self.sentinel.nexts[0];
            for (0..i) |_| {
                node = node.?.nexts[0];
            }
            return node.?.value;
        }
    };
}

test "set operations" {
    var set = try SkiplistSSet(i32, 5).init(testing.allocator);
    defer set.deinit();
    try testing.expect(try set.add(1));
    try testing.expect(try set.add(5));
    try testing.expect(try set.add(7));
    try testing.expect(try set.add(11));
    try testing.expect(try set.add(3));
    try testing.expect(try set.add(9));
    try testing.expectEqual(false, try set.add(1));
    try testing.expectEqual(false, try set.add(3));
    try testing.expectEqual(6, set.size);

    try testing.expectEqual(1, set.find(0));
    try testing.expectEqual(1, set.find(1));
    try testing.expectEqual(3, set.find(2));
    try testing.expectEqual(3, set.find(3));
    try testing.expectEqual(5, set.find(4));
    try testing.expectEqual(5, set.find(5));
    try testing.expectEqual(7, set.find(6));
    try testing.expectEqual(7, set.find(7));
    try testing.expectEqual(9, set.find(8));
    try testing.expectEqual(9, set.find(9));
    try testing.expectEqual(11, set.find(10));
    try testing.expectEqual(11, set.find(11));
    try testing.expectEqual(null, set.find(12));

    for (0.., [_]i32{ 1, 3, 5, 7, 9, 11 }) |i, expected| {
        try testing.expectEqual(expected, set.get(i));
    }
    try testing.expectEqual(false, try set.remove(0));
    try testing.expectEqual(true, try set.remove(3));
    try testing.expectEqual(false, try set.remove(6));
    try testing.expectEqual(true, try set.remove(9));
    try testing.expectEqual(false, try set.remove(12));
    try testing.expectEqual(4, set.size);
    for (0.., [_]i32{ 1, 5, 7, 11 }) |i, expected| {
        try testing.expectEqual(expected, set.get(i));
    }
}
