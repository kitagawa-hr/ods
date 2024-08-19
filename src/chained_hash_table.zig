const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const Allocator = mem.Allocator;

const ArrayStack = @import("array_stack.zig").ArrayStack;
const MultiplicativeHash = @import("hash.zig").MultiplicativeHash;
const hashCode = @import("hash.zig").hashCode;

pub fn ChainedHashTable(comptime T: type) type {
    return struct {
        const Self = @This();
        /// table[hash(x)] contains x
        /// table.len must be greater than or equal to size
        table: []*ArrayStack(T),
        /// Number of elements.
        size: usize,
        /// dimension of the table (~ log(size))
        d: u8,
        hasher: MultiplicativeHash,
        allocator: Allocator,

        pub fn init(allocator: Allocator) !Self {
            return Self{
                .table = try allocTable(allocator, 2),
                .size = 0,
                .allocator = allocator,
                .d = 1,
                .hasher = try MultiplicativeHash.init(),
            };
        }
        fn allocTable(allocator: Allocator, n: usize) Allocator.Error![]*ArrayStack(T) {
            const table = try allocator.alloc(*ArrayStack(T), n);
            for (0..n) |i| {
                const arr = try allocator.create(ArrayStack(T));
                arr.* = try ArrayStack(T).init(allocator);
                table[i] = arr;
            }
            return table;
        }

        fn freeTable(self: Self, table: []*ArrayStack(T)) void {
            for (0..table.len) |i| {
                table[i].deinit();
                self.allocator.destroy(table[i]);
            }
            self.allocator.free(table);
        }

        pub fn deinit(self: Self) void {
            self.freeTable(self.table);
        }

        pub fn hash(self: Self, x: T) usize {
            return self.hasher.hash(hashCode(T, x), self.d);
        }

        pub fn find(self: Self, x: T) ?T {
            const bucket = self.table[self.hash(x)];
            for (0..bucket.size) |i| {
                if (bucket.get(i) == x) {
                    return x;
                }
            }
            return null;
        }

        pub fn add(self: *Self, x: T) Allocator.Error!bool {
            if (self.find(x) != null) {
                return false;
            }
            if (self.size > self.table.len) {
                try self.resize();
            }
            const bucket = self.table[self.hash(x)];
            try bucket.add(bucket.size, x);
            self.size += 1;
            return true;
        }

        pub fn remove(self: *Self, x: T) Allocator.Error!?T {
            const bucket = self.table[self.hash(x)];
            for (0..bucket.size) |i| {
                if (bucket.get(i) == x) {
                    self.size -= 1;
                    return try bucket.remove(i);
                }
            }
            return null;
        }

        fn resize(self: *Self) Allocator.Error!void {
            self.d = blk: {
                var d: u8 = 1;
                while (std.math.shl(u8, 1, d) <= self.size) {
                    d += 1;
                }
                break :blk d;
            };
            const new_table = try allocTable(
                self.allocator,
                std.math.shl(usize, 1, self.d),
            );
            for (0..self.table.len) |i| {
                for (0..self.table[i].size) |j| {
                    const value = self.table[i].get(j);
                    const bucket = new_table[self.hash(value)];
                    try bucket.add(bucket.size, value);
                }
            }
            self.freeTable(self.table);
            self.table = new_table;
        }
    };
}

test "uset operations" {
    var set = try ChainedHashTable(i32).init(testing.allocator);
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
