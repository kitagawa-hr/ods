const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayDeque = @import("./array_deque.zig").ArrayDeque;

/// Bounded deque.
fn BDeque(comptime T: type) type {
    return struct {
        const Self = @This();
        a: []T,
        head: usize,
        size: usize,
        allocator: Allocator,

        pub fn init(allocator: mem.Allocator, size: usize) Allocator.Error!Self {
            return Self{
                .a = try allocator.alloc(T, size),
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

        fn check_index(self: Self, i: usize) void {
            if (i < 0 or i >= self.size) {
                std.debug.panic("index out of bounds. size: {d}, i: {d}", .{ self.size, i });
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
            if (i < 0 or i > self.size) {
                std.debug.panic("index out of bounds. size: {d}, i: {d}", .{ self.size, i });
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

        pub fn remove(self: *Self, i: usize) T {
            const x = self.get(i);
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

/// Space-Efficient doubly linked list.
/// Each node contains from b-1 to b+1 elements where b is block_size.
pub fn SEList(comptime T: type) type {
    return struct {
        const Self = @This();
        const Node = struct {
            data: *BDeque(T),
            next: *Node,
            prev: *Node,
        };
        const Location = struct {
            node: *Node,
            offset: usize,
        };
        sentinel: *Node,
        size: usize,
        allocator: Allocator,
        block_size: usize,

        pub fn init(allocator: Allocator, block_size: usize) Allocator.Error!Self {
            const sentinel = try allocNode(allocator, block_size);
            return Self{
                .sentinel = sentinel,
                .size = 0,
                .allocator = allocator,
                .block_size = block_size,
            };
        }

        fn allocNode(allocator: Allocator, block_size: usize) Allocator.Error!*Node {
            const node = try allocator.create(Node);
            const data = try allocator.create(BDeque(T));
            data.* = try BDeque(T).init(allocator, block_size + 1);
            node.* = Node{
                .data = data,
                .next = node,
                .prev = node,
            };
            return node;
        }

        fn freeNode(self: Self, node: *Node) void {
            node.data.deinit();
            self.allocator.destroy(node.data);
            self.allocator.destroy(node);
        }

        pub fn deinit(self: Self) void {
            var node = self.sentinel.next;
            while (node != self.sentinel) {
                const target_node = node;
                node = node.next;
                self.freeNode(target_node);
            }
            self.freeNode(self.sentinel);
        }

        fn getLocation(self: Self, i: usize) Location {
            if (i < self.size / 2) {
                var j = i;
                var node = self.sentinel.next;
                while (j >= node.data.size) {
                    j -= node.data.size;
                    node = node.next;
                }
                return Location{ .node = node, .offset = j };
            } else {
                var j = self.size;
                var node = self.sentinel;
                while (i < j) {
                    node = node.prev;
                    j -= node.data.size;
                }
                return Location{ .node = node, .offset = i - j };
            }
        }

        fn addBefore(self: *Self, node: *Node) Allocator.Error!*Node {
            // [node.prev, node] to [node.prev, new_node, node]
            const new_node = try allocNode(self.allocator, self.block_size);
            new_node.next = node;
            new_node.prev = node.prev;
            new_node.next.prev = new_node;
            new_node.prev.next = new_node;
            return new_node;
        }

        fn removeNode(self: *Self, node: *Node) void {
            // [node.prev, node, node.next] to [node.prev, node.next]
            node.prev.next = node.next;
            node.next.prev = node.prev;
            self.freeNode(node);
        }

        /// b nodes with b-1 elements to b-1 nodes with b elements.
        ///  |a|b|.|.| |c|d|.|.| |e|f|.|.|
        ///  |a|b|c|.| |d|e|f|.|
        fn gather(self: *Self, node: *Node) Allocator.Error!void {
            var u = node;
            for (0..self.block_size - 1) |_| {
                while (u.data.size < self.block_size) {
                    try u.data.add(u.data.size, u.next.data.remove(0));
                }
                u = u.next;
            }
            self.removeNode(u);
        }

        /// Remove element at i-th position.
        ///
        ///  Three cases are considered:
        ///
        ///  * shift
        ///  |a|b|.|.| |c|d|.|.| |e|f|g|.|
        ///  remove(1)
        ///  |a|.|.|.| |c|d|.|.| |e|f|g|.|
        ///  |a|c|.|.| |d|e|.|.| |f|g|.|.|
        ///
        ///  * gather
        ///  (b-1)*b to b*(b-1)
        ///  |a|b|.|.| |c|d|.|.| |e|f|.|.|
        ///  remove(1)
        ///  |a|b|c|.| |d|e|f|.|
        ///  |a|c|.|.| |d|e|f|.|
        pub fn remove(self: *Self, i: usize) Allocator.Error!T {
            const location = self.getLocation(i);
            const r = blk: {
                var j: usize = 0;
                var node = location.node;
                while (node.data.size == self.block_size - 1 and node != self.sentinel and j < self.block_size) {
                    node = node.next;
                    j += 1;
                }
                break :blk j;
            };
            if (r == self.block_size) {
                try self.gather(location.node);
            }
            const x = location.node.data.remove(location.offset);
            var node = location.node;
            // shift
            while (node.data.size < self.block_size - 1 and node.next != self.sentinel) {
                try node.data.add(node.data.size, node.next.data.remove(0));
                node = node.next;
            }
            if (self.sentinel.prev.data.size == 0) {
                self.removeNode(node);
            }
            self.size -= 1;
            return x;
        }

        fn addLast(self: *Self, x: T) Allocator.Error!void {
            var last = self.sentinel.prev;
            if (last == self.sentinel or last.data.size == self.block_size + 1) {
                last = try self.addBefore(self.sentinel);
            }
            try last.data.add(last.data.size, x);
            self.size += 1;
        }

        /// b nodes with b+1 elements to b+1 nodes with b elements.
        /// Example: b = 2
        /// |a|b|c| |d|e|f|
        /// |a|b|.| |c|d|.| |e|f|.|
        fn spread(self: *Self, node: *Node) Allocator.Error!void {
            var u = node;
            for (0..self.block_size) |_| {
                u = u.next;
            }
            u = try self.addBefore(u);
            while (u != node) {
                while (u.data.size < self.block_size) {
                    try u.data.add(0, u.prev.data.remove(u.prev.data.size - 1));
                }
                u = u.prev;
            }
        }

        /// Add x at i-th position.
        ///
        ///  The following cases are considered:
        ///
        ///  * add a new node to last
        ///  |a|b|c|d|
        ///  add(3,e)
        ///  |a|b|c|d| |.|.|.|.|
        ///  |a|b|c|.| |d|.|.|.|
        ///  |a|b|c|e| |d|.|.|.|
        ///
        ///  * shift
        ///  |a|b|c|d| |e|f|g|.| |h|i|j|.|
        ///  add(1, x)
        ///  |a|b|c|.| |d|e|f|g| |h|i|j|.|
        ///  |a|x|b|c| |d|e|f|g| |h|i|j|.|
        ///
        ///  * spread
        ///  (b+1)*b to b*(b+1)
        ///  |a|x|y|b| |c|d|e|f| |g|h|i|j|
        ///  add(3, z)
        ///  |a|x|y|.| |b|c|d|.| |e|f|g|.| |h|i|j|.|
        ///  |a|x|y|z| |b|c|d|.| |e|f|g|.| |h|i|j|.|
        pub fn add(self: *Self, i: usize, x: T) Allocator.Error!void {
            if (i == self.size) {
                try self.addLast(x);
                return;
            }
            const location = self.getLocation(i);
            var r: usize = 0;
            var node = location.node;
            while (node.data.size == self.block_size + 1 and node != self.sentinel and r < self.block_size) {
                node = node.next;
                r += 1;
            }
            if (r == self.block_size) {
                try self.spread(location.node);
                node = location.node;
            }
            if (node == self.sentinel) {
                node = try self.addBefore(self.sentinel);
            }
            // shift
            while (node != location.node) {
                try node.data.add(0, node.prev.data.remove(node.prev.data.size - 1));
                node = node.prev;
            }
            try node.data.add(location.offset, x);
            self.size += 1;
        }

        pub fn get(self: Self, i: usize) T {
            const location = self.getLocation(i);
            return location.node.data.get(location.offset);
        }

        pub fn set(self: *Self, i: usize, value: T) void {
            const location = self.getLocation(i);
            location.node.data.set(location.offset, value);
        }
    };
}

test "list operations" {
    var list = try SEList(i32).init(testing.allocator, 2);
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
    var list = try SEList(usize).init(testing.allocator, 30);
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
        try testing.expectEqual(std_list.orderedRemove(i * i - i), try list.remove(i * i - i));
    }
    // assert all elements
    try testing.expectEqual(std_list.items.len, list.size);
    for (0..std_list.items.len) |i| {
        try testing.expectEqual(std_list.items[i], list.get(i));
    }
}
