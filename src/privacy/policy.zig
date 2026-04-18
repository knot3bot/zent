const std = @import("std");

/// Operation kind for privacy evaluation.
pub const Op = enum {
    query,
    create,
    update,
    delete,
};

/// Decision returned by a privacy rule.
pub const Decision = enum {
    allow,
    deny,
};

/// Backward compatibility: old-style rule function.
pub const OldRule = *const fn (op: Op, table: []const u8) Decision;

/// Privacy policy that can be attached to a schema.
/// Backward compatible format with separate query and mutation rules.
pub const Policy = struct {
    query: ?OldRule = null,
    mutation: ?OldRule = null,

    pub fn evalQuery(self: Policy, op: Op, table: []const u8) Decision {
        if (self.query) |rule| return rule(op, table);
        return .allow;
    }

    pub fn evalMutation(self: Policy, op: Op, table: []const u8) Decision {
        if (self.mutation) |rule| return rule(op, table);
        return .allow;
    }
};

// ------------------------------------------------------------------
// Built-in rules
// ------------------------------------------------------------------

pub fn AlwaysAllow(_: Op, _: []const u8) Decision {
    return .allow;
}

pub fn AlwaysDeny(_: Op, _: []const u8) Decision {
    return .deny;
}

pub fn OnCreate(op: Op, _: []const u8) Decision {
    return if (op == .create) .allow else .deny;
}

pub fn OnUpdate(op: Op, _: []const u8) Decision {
    return if (op == .update) .allow else .deny;
}

pub fn OnDelete(op: Op, _: []const u8) Decision {
    return if (op == .delete) .allow else .deny;
}

pub fn OnQuery(op: Op, _: []const u8) Decision {
    return if (op == .query) .allow else .deny;
}

// ------------------------------------------------------------------
// Tests
// ------------------------------------------------------------------

test "Built-in rules" {
    try std.testing.expectEqual(Decision.allow, OnCreate(.create, "user"));
    try std.testing.expectEqual(Decision.deny, OnCreate(.update, "user"));

    try std.testing.expectEqual(Decision.allow, OnQuery(.query, "user"));
    try std.testing.expectEqual(Decision.deny, OnQuery(.create, "user"));
}

test "Policy evaluation" {
    const p = Policy{ .mutation = OnCreate };
    try std.testing.expectEqual(Decision.allow, p.evalMutation(.create, "user"));
    try std.testing.expectEqual(Decision.deny, p.evalMutation(.update, "user"));
    try std.testing.expectEqual(Decision.allow, p.evalQuery(.query, "user"));
}
