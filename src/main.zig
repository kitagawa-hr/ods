const std = @import("std");

pub const array_stack = @import("./array_stack.zig");

comptime {
    std.testing.refAllDecls(@This());
}
