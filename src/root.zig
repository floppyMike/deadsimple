const std = @import("std");

pub const cli = @import("cli.zig");

test {
    std.testing.refAllDecls(@This());
}
