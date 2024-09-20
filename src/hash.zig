const std = @import("std");
const testing = std.testing;

pub fn hashCode(comptime T: type, x: T) u64 {
    var hasher = std.hash.XxHash64.init(0);
    std.hash.autoHash(&hasher, x);
    return hasher.final();
}

/// Knuth's Multiplicative Hash
/// hash(x) = ((z*x) mod 2^w ) div 2^(w−d)
///
/// Args:
///   x: The value to hash
///   d: The number of bits to keep
///   z: odd number
pub const MultiplicativeHash = struct {
    /// w: number of bits of usize
    const w = @sizeOf(usize) * 8;
    /// z: odd number
    z: usize,

    pub fn init() !MultiplicativeHash {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        var prng = std.rand.DefaultPrng.init(seed);
        const rand = prng.random();
        const z = rand.int(usize) | 1;
        return MultiplicativeHash{ .z = z };
    }

    pub fn hash(self: MultiplicativeHash, x: usize, d: u8) usize {
        const t: usize = @truncate(@as(u128, self.z) * @as(u128, x));
        return std.math.shr(usize, t, w - d);
    }
};

pub const TabulationHash = struct {
    const w: comptime_int = @sizeOf(usize) * 8;
    const c: comptime_int = w / 8;
    const n: comptime_int = 1 << w / 8;
    tab: [c][n]usize,

    pub fn init() !TabulationHash {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        var prng = std.rand.DefaultPrng.init(seed);
        const rand = prng.random();
        const tab = blk: {
            var arr: [c][n]usize = undefined;
            for (0..c) |i| {
                for (0..n) |j| {
                    arr[i][j] = rand.int(usize);
                }
            }
            break :blk arr;
        };
        return TabulationHash{ .tab = tab };
    }

    /// x -> x[0], x[1], ..., x[c-1]
    /// hash(x) = T[0][x[0]] ^ T[1][x[1]] ^ ... ^ T[c-1][x[c-1]]
    ///
    /// Args:
    ///   x: The value to hash
    ///   d: The number of bits to keep
    pub fn hash(self: TabulationHash, x: usize, d: u8) usize {
        var h: usize = 0;
        for (0..c) |i| {
            const idx = std.math.shr(usize, x, i * 8) & 0xff;
            h ^= self.tab[i][idx];
        }
        return std.math.shr(usize, h, w - d);
    }
};

test "test multiplicativeHash" {
    const hasher = try MultiplicativeHash.init();
    var seed: u64 = undefined;
    try std.posix.getrandom(std.mem.asBytes(&seed));
    var prng = std.rand.DefaultPrng.init(seed);
    const rand = prng.random();
    const d = 50;
    const testSize = 1000;
    var results: [testSize]usize = undefined;
    for (0..testSize) |i| {
        const x = rand.int(usize);
        const h = hasher.hash(x, d);
        try testing.expectEqual(h, hasher.hash(x, d));
        try testing.expect(h < 1 << d);
        results[i] = h;
    }
    std.mem.sort(usize, &results, {}, comptime std.sort.asc(usize));
    const duplicatedCount = blk: {
        var c: usize = 0;
        for (1..results.len) |i| {
            if (results[i] == results[i - 1]) {
                c += 1;
            }
        }
        break :blk c;
    };
    // Possibility of collision ~ testSize^2/2^d(~ 1/10^9 for testSize=1000, d=50)
    try testing.expect(duplicatedCount == 0);
}

test "test TabulationHash" {
    const hasher = try TabulationHash.init();
    var seed: u64 = undefined;
    try std.posix.getrandom(std.mem.asBytes(&seed));
    var prng = std.rand.DefaultPrng.init(seed);
    const rand = prng.random();
    const d = 50;
    const testSize = 1000;
    var results: [testSize]usize = undefined;
    for (0..testSize) |i| {
        const x = rand.int(usize);
        const h = hasher.hash(x, d);
        try testing.expectEqual(h, hasher.hash(x, d));
        try testing.expect(h < 1 << d);
        results[i] = h;
    }
    std.mem.sort(usize, &results, {}, comptime std.sort.asc(usize));
    const duplicatedCount = blk: {
        var c: usize = 0;
        for (1..results.len) |i| {
            if (results[i] == results[i - 1]) {
                c += 1;
            }
        }
        break :blk c;
    };
    // Possibility of collision ~ testSize^2/2^d(~ 1/10^9 for testSize=1000, d=50)
    try testing.expect(duplicatedCount == 0);
}
