const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const Allocator = mem.Allocator;

pub fn Skiplist(comptime T: type, comptime max_height: u8) type {
    return struct {
        const Self = @This();
        /// Node of the skiplist.
        /// lengths[i] is edge length and nexts[i] is edge destination
        const Node = struct {
            value: T,
            height: u8,
            lengths: []usize,
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
            var lengths = try allocator.alloc(usize, height);
            for (0..height) |y| {
                nexts[y] = null;
                lengths[y] = 1;
            }
            node.* = .{
                .value = undefined,
                .height = height,
                .lengths = lengths,
                .nexts = nexts,
            };
            return node;
        }

        fn freeNode(self: Self, node: *Node) void {
            self.allocator.free(node.nexts);
            self.allocator.free(node.lengths);
            self.allocator.destroy(node);
        }

        fn findPredNode(self: Self, i: usize) *Node {
            // Since sentinel is indexed as 0, the index of the element is i + 1.
            const index = i + 1;
            var node: *Node = self.sentinel;
            var j: usize = 0;
            var height = max_height;
            while (height > 0) : (height -= 1) {
                const h = height - 1;
                while (node.nexts[h]) |next_node| {
                    if (j + node.lengths[h] >= index) {
                        break;
                    }
                    j += node.lengths[h];
                    node = next_node;
                }
            }
            return node;
        }

        pub fn get(self: Self, i: usize) T {
            std.debug.assert(0 <= i and i < self.size);
            return self.findPredNode(i).nexts[0].?.value;
        }

        pub fn set(self: Self, i: usize, x: T) void {
            std.debug.assert(0 <= i and i < self.size);
            const node = self.findPredNode(i).nexts[0].?;
            node.value = x;
        }

        fn pickHeight() !u8 {
            var seed: u64 = undefined;
            try std.posix.getrandom(std.mem.asBytes(&seed));
            var prng = std.rand.DefaultPrng.init(seed);
            const rand = prng.random();
            return rand.intRangeAtMost(u8, 1, max_height);
        }

        fn addNode(self: *Self, i: usize, new_node: *Node) !void {
            // Since sentinel is indexed as 0, the actual index of the element is i + 1.
            const index = i + 1;
            var node: *Node = self.sentinel;
            var j: usize = 0;
            var height = max_height;
            while (height > 0) : (height -= 1) {
                const h = height - 1;
                while (node.nexts[h]) |next_node| {
                    if (j + node.lengths[h] >= index) {
                        break;
                    }
                    j += node.lengths[h];
                    node = next_node;
                }
                node.lengths[h] += 1;
                if (height <= new_node.height) {
                    new_node.nexts[h] = node.nexts[h];
                    node.nexts[h] = new_node;
                    new_node.lengths[h] = node.lengths[h] - (index - j);
                    node.lengths[h] = index - j;
                }
            }
            self.size += 1;
        }

        pub fn add(self: *Self, i: usize, x: T) !void {
            std.debug.assert(0 <= i and i <= self.size);
            const new_height = try pickHeight();
            const new_node = try allocNode(self.allocator, new_height);
            new_node.value = x;
            try self.addNode(i, new_node);
        }

        pub fn remove(self: *Self, i: usize) T {
            std.debug.assert(0 <= i and i < self.size);
            // Since sentinel is indexed as 0, the actual index of the element is i + 1.
            const index = i + 1;
            var node: *Node = self.sentinel;
            var height = max_height;
            var j: usize = 0;
            var removed_node: *Node = undefined;
            while (height > 0) : (height -= 1) {
                const h = height - 1;
                while (node.nexts[h]) |next_node| {
                    if (j + node.lengths[h] >= index) {
                        break;
                    }
                    j += node.lengths[h];
                    node = next_node;
                }
                node.lengths[h] -= 1;
                if (j + node.lengths[h] + 1 == index) {
                    removed_node = node.nexts[h].?;
                    node.nexts[h] = removed_node.nexts[h];
                    node.lengths[h] += removed_node.lengths[h];
                }
            }
            const x = removed_node.value;
            self.freeNode(removed_node);
            self.size -= 1;
            return x;
        }
    };
}

test "list operations" {
    var list = try Skiplist(i32, 5).init(testing.allocator);
    defer list.deinit();
    try list.add(0, 1); // [1]
    try list.add(1, 2); // [1, 2]
    try list.add(2, 3); // [1, 2, 3]
    try list.add(1, 4); // [1, 4, 2, 3]
    try list.add(2, 5); // [1, 4, 5, 2, 3]
    try testing.expectEqual(5, list.size);
    for (0.., [_]i32{ 1, 4, 5, 2, 3 }) |i, expected| {
        try testing.expectEqual(expected, list.get(i));
    }
    try testing.expectEqual(4, list.remove(1)); // [1, 5, 2, 3]
    try testing.expectEqual(5, list.remove(1)); // [1, 2, 3]
    try list.add(1, 6); // [1, 6, 2, 3]
    try list.add(3, 7); // [1, 6, 2, 7, 3]
    try list.add(0, 8); // [8, 1, 6, 2, 7, 3]
    for (0.., [_]i32{ 8, 1, 6, 2, 7, 3 }) |i, expected| {
        try testing.expectEqual(expected, list.get(i));
    }
    try testing.expectEqual(2, list.remove(3)); // [8, 1, 6, 7, 3]
    try testing.expectEqual(7, list.remove(3)); // [8, 1, 6, 3]
    try testing.expectEqual(6, list.remove(2)); // [8, 1, 3]
    for (0.., [_]i32{ 8, 1, 3 }) |i, expected| {
        try testing.expectEqual(expected, list.get(i));
    }
}

test "with large data using std.ArrayList" {
    var std_list = std.ArrayList(usize).init(testing.allocator);
    var list = try Skiplist(usize, 16).init(testing.allocator);
    defer std_list.deinit();
    defer list.deinit();
    // add last
    for (0..500) |i| {
        try std_list.append(i);
        try list.add(i, i);
    }
    // add first
    for (0..500) |i| {
        try std_list.insert(0, i);
        try list.add(0, i);
    }
    // add random
    for (0..30) |i| {
        try std_list.insert(i * i, i * i);
        try list.add(i * i, i * i);
    }
    // set
    for (300..800) |i| {
        std_list.items[i] = i;
        list.set(i, i);
    }
    // remove random
    for (0..30) |i| {
        try testing.expectEqual(std_list.orderedRemove(i * i - i), list.remove(i * i - i));
    }
    // assert all elements
    try testing.expectEqual(std_list.items.len, list.size);
    for (0..std_list.items.len) |i| {
        try testing.expectEqual(std_list.items[i], list.get(i));
    }
}
