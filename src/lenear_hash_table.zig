const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const Allocator = mem.Allocator;
const hashCode = @import("hash.zig").hashCode;
const TabulationHash = @import("hash.zig").TabulationHash;

pub fn LenearHashTable(comptime T: type) type {
    return struct {
        const Self = @This();
        /// table[hash(x)] contains x
        /// table.len must be greater than or equal to size
        table: []Elem,
        /// Number of Elem.value
        size: usize,
        /// Number of Elem.value and Elem.deleted
        /// 2 * q <= table.len must be satisfied.
        q: usize,
        /// dimension of the table
        /// 2^d = table.len
        d: u8,
        hasher: TabulationHash,
        allocator: Allocator,

        const Elem = union(enum) {
            none,
            deleted,
            value: T,
        };

        pub fn init(allocator: Allocator) !Self {
            return Self{
                .table = try allocTable(allocator, 2),
                .size = 0,
                .allocator = allocator,
                .d = 1,
                .q = 0,
                .hasher = try TabulationHash.init(),
            };
        }

        fn allocTable(allocator: Allocator, n: usize) Allocator.Error![]Elem {
            const table = try allocator.alloc(Elem, n);
            for (0..n) |i| {
                table[i] = Elem.none;
            }
            return table;
        }

        pub fn deinit(self: Self) void {
            self.allocator.free(self.table);
        }

        /// Tabulation Hashing
        pub fn hash(self: Self, x: T) usize {
            return self.hasher.hash(hashCode(T, x), self.d);
        }

        pub fn find(self: Self, x: T) ?T {
            var i = self.hash(x);
            while (self.table[i] != Elem.none) {
                switch (self.table[i]) {
                    .value => |v| {
                        if (v == x) return v;
                    },
                    else => {},
                }
                if (i == self.table.len - 1) {
                    i = 0;
                } else {
                    i += 1;
                }
            }
            return null;
        }

        pub fn add(self: *Self, x: T) Allocator.Error!bool {
            if (self.find(x) != null) {
                return false;
            }
            if (2 * (self.q + 1) > self.table.len) {
                try self.resize();
            }

            var i = self.hash(x);
            while (self.table[i] != Elem.none and self.table[i] != Elem.deleted) {
                if (i == self.table.len - 1) {
                    i = 0;
                } else {
                    i += 1;
                }
            }
            if (self.table[i] == Elem.none) {
                self.q += 1;
            }
            self.table[i] = Elem{ .value = x };
            self.size += 1;
            return true;
        }

        pub fn remove(self: *Self, x: T) Allocator.Error!?T {
            var i = self.hash(x);
            while (true) {
                switch (self.table[i]) {
                    .none => {
                        return null;
                    },
                    .deleted => {},
                    .value => |v| {
                        if (v == x) {
                            self.table[i] = Elem.deleted;
                            self.size -= 1;
                            self.q -= 1;
                            if (8 * self.size < self.table.len) {
                                try self.resize();
                            }
                            return v;
                        }
                    },
                }
                if (i == self.table.len - 1) {
                    i = 0;
                } else {
                    i += 1;
                }
            }
        }

        fn resize(self: *Self) Allocator.Error!void {
            self.d = blk: {
                var d: u8 = 1;
                while (std.math.shl(u8, 1, d) < 3 * self.size) {
                    d += 1;
                }
                break :blk d;
            };
            const new_table = try allocTable(
                self.allocator,
                std.math.shl(usize, 1, self.d),
            );
            for (0..self.table.len) |i| {
                switch (self.table[i]) {
                    .none => {},
                    .deleted => {},
                    .value => |v| {
                        var j = self.hash(v);
                        while (new_table[j] != Elem.none) {
                            if (j == new_table.len) {
                                j = 0;
                            } else {
                                j += 1;
                            }
                        }
                        new_table[j] = Elem{ .value = v };
                    },
                }
            }
            self.allocator.free(self.table);
            self.table = new_table;
            self.q = self.size;
        }
    };
}

test "uset operations" {
    var set = try LenearHashTable(i32).init(testing.allocator);
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

    // // remove
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
