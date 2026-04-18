const std = @import("std");

/// Operation type for hooks.
pub const Op = enum {
    create,
    update,
    delete,
};

/// A simple hook that can run before or after a mutation.
pub const Hook = struct {
    op: Op,
    before: ?*const fn (op: Op, table_name: []const u8) void = null,
    after: ?*const fn (op: Op, table_name: []const u8) void = null,
};

// ------------------------------------------------------------------
// Tests
// ------------------------------------------------------------------

test "Hook basic functionality" {
    const hook = Hook{ .op = .create };
    try std.testing.expectEqual(Op.create, hook.op);
}
