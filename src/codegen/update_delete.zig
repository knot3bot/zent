const std = @import("std");
const TypeInfo = @import("graph.zig").TypeInfo;
const FieldInfo = @import("graph.zig").FieldInfo;
const sql = @import("../sql/builder.zig");
const sql_driver = @import("../sql/driver.zig");
const Dialect = @import("../sql/dialect.zig").Dialect;
const Hook = @import("../runtime/hook.zig").Hook;
const Op = @import("../runtime/hook.zig").Op;
const privacy = @import("../privacy/policy.zig");

const FieldValue = @import("create.zig").FieldValue;

/// Generate an Update builder for an entity.
pub fn UpdateBuilder(comptime info: TypeInfo) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        driver: sql_driver.Driver,
        values: std.array_list.Managed(FieldValue),
        predicates: std.array_list.Managed(sql.Predicate),
        json_strings: std.array_list.Managed([]const u8),
        hooks: []const Hook,

        pub fn init(allocator: std.mem.Allocator, driver: sql_driver.Driver, hooks: []const Hook) Self {
            return .{
                .allocator = allocator,
                .driver = driver,
                .hooks = hooks,
                .values = std.array_list.Managed(FieldValue).init(allocator),
                .predicates = std.array_list.Managed(sql.Predicate).init(allocator),
                .json_strings = std.array_list.Managed([]const u8).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.json_strings.items) |s| self.allocator.free(s);
            self.json_strings.deinit();
            self.values.deinit();
            self.predicates.deinit();
        }

        /// Set a field value dynamically (no compile-time checking).
        pub fn set(self: *Self, field_name: []const u8, value: sql.Value) *Self {
            self.values.append(.{ .name = field_name, .value = value }) catch unreachable;
            return self;
        }

        /// Set a field value with compile-time name and type checking.
        pub fn setFieldValue(self: *Self, comptime field_name: []const u8, value: anytype) *Self {
            comptime var needs_json = false;
            comptime {
                var found = false;
                for (info.fields) |f| {
                    if (std.mem.eql(u8, f.name, field_name)) {
                        const Expected = f.zig_type;
                        const Actual = @TypeOf(value);
                        if (!canSetField(Expected, Actual)) {
                            @compileError("Type mismatch for field '" ++ field_name ++ "': expected " ++ @typeName(Expected) ++ ", got " ++ @typeName(Actual));
                        }
                        if (f.field_type == .enum_ and f.enum_values.len > 0) {
                            const actual_info = @typeInfo(Actual);
                            if (actual_info == .array and actual_info.array.child == u8) {
                                var valid = false;
                                for (f.enum_values) |ev| {
                                    if (std.mem.eql(u8, ev, value)) valid = true;
                                }
                                if (!valid) @compileError("Invalid enum value for field '" ++ field_name ++ "': '" ++ value ++ "'");
                            }
                        }
                        if (f.field_type == .json and @typeInfo(Actual) == .@"struct") {
                            needs_json = true;
                        }
                        found = true;
                        break;
                    }
                }
                if (!found) @compileError("Unknown field: " ++ field_name);
            }

            if (comptime needs_json) {
                const json_str = std.json.Stringify.valueAlloc(self.allocator, value, .{}) catch unreachable;
                self.json_strings.append(json_str) catch unreachable;
                return self.set(field_name, .{ .string = json_str });
            }

            return self.set(field_name, toSqlValue(value));
        }

        /// Add predicates for WHERE clause.
        pub fn Where(self: *Self, predicates: anytype) *Self {
            switch (@typeInfo(@TypeOf(predicates))) {
                .pointer, .array => {
                    for (predicates) |p| {
                        self.predicates.append(p) catch unreachable;
                    }
                },
                .@"struct" => |s| {
                    if (s.is_tuple) {
                        inline for (predicates) |p| {
                            self.predicates.append(p) catch unreachable;
                        }
                    } else {
                        @compileError("Where expects a tuple or slice of sql.Predicate");
                    }
                },
                else => @compileError("Where expects a tuple or slice of sql.Predicate"),
            }
            return self;
        }

        /// Execute the UPDATE and return rows affected.
        pub fn Save(self: *Self) !usize {
            if (info.policy) |p| {
                if (p.evalMutation(.update, info.table_name) == .deny) {
                    return error.PrivacyDenied;
                }
            }
            for (self.hooks) |h| {
                if (h.op == .update) {
                    if (h.before) |f| f(.update, info.table_name);
                }
            }
            defer {
                for (self.hooks) |h| {
                    if (h.op == .update) {
                        if (h.after) |f| f(.update, info.table_name);
                    }
                }
            }

            var builder = sql.Update(self.allocator, self.driver.dialect(), info.table_name);
            defer builder.deinit();

            for (self.values.items) |fv| {
                _ = builder.set(fv.name, fv.value);
            }

            for (self.predicates.items) |pred| {
                _ = builder.where(pred);
            }

            const q = try builder.query();
            const res = try self.driver.exec(q.sql, q.args);
            return res.rows_affected;
        }

        fn isStringLike(comptime T: type) bool {
            return switch (@typeInfo(T)) {
                .pointer => |ptr| {
                    if (ptr.size == .slice and ptr.child == u8) return true;
                    // Check for pointers to u8 arrays like *const [N:0]u8
                    if (ptr.size == .one) {
                        return switch (@typeInfo(ptr.child)) {
                            .array => |arr| arr.child == u8,
                            else => false,
                        };
                    }
                    return false;
                },
                .array => |arr| arr.child == u8,
                else => false,
            };
        }

        fn canSetField(comptime Expected: type, Actual: type) bool {
            // Unwrap optional type for comparison
            const Unwrapped = if (@typeInfo(Expected) == .optional)
                @typeInfo(Expected).optional.child
            else
                Expected;

            // Direct match
            if (Expected == Actual) return true;
            // int literals
            if (Unwrapped == i64 and Actual == comptime_int) return true;
            if (Unwrapped == f64 and Actual == comptime_float) return true;
            // String types - check various pointer/array forms
            if (Unwrapped == []const u8) {
                return switch (@typeInfo(Actual)) {
                    .pointer => |ptr| {
                        if (ptr.child == u8 and ptr.size == .slice) return true;
                        // Check for pointers to u8 arrays like *const [N:0]u8
                        if (ptr.size == .one) {
                            return switch (@typeInfo(ptr.child)) {
                                .array => |arr| arr.child == u8,
                                else => false,
                            };
                        }
                        return false;
                    },
                    .array => |arr| arr.child == u8,
                    else => false,
                };
            }
            return false;
        }

        fn toSqlValue(v: anytype) sql.Value {
            const T = @TypeOf(v);
            if (T == comptime_int) return .{ .int = v };
            if (T == comptime_float) return .{ .float = v };
            return switch (@typeInfo(T)) {
                .bool => .{ .bool = v },
                .int => .{ .int = v },
                .float => .{ .float = v },
                else => {
                    if (isStringLike(T)) return .{ .string = v };
                    @compileError("Unsupported value type: " ++ @typeName(T));
                },
            };
        }
    };
}

/// Generate a Delete builder for an entity.
pub fn DeleteBuilder(comptime info: TypeInfo) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        driver: sql_driver.Driver,
        predicates: std.array_list.Managed(sql.Predicate),
        hooks: []const Hook,

        pub fn init(allocator: std.mem.Allocator, driver: sql_driver.Driver, hooks: []const Hook) Self {
            return .{
                .allocator = allocator,
                .driver = driver,
                .hooks = hooks,
                .predicates = std.array_list.Managed(sql.Predicate).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.predicates.deinit();
        }

        /// Add predicates for WHERE clause.
        pub fn Where(self: *Self, predicates: anytype) *Self {
            switch (@typeInfo(@TypeOf(predicates))) {
                .pointer, .array => {
                    for (predicates) |p| {
                        self.predicates.append(p) catch unreachable;
                    }
                },
                .@"struct" => |s| {
                    if (s.is_tuple) {
                        inline for (predicates) |p| {
                            self.predicates.append(p) catch unreachable;
                        }
                    } else {
                        @compileError("Where expects a tuple or slice of sql.Predicate");
                    }
                },
                else => @compileError("Where expects a tuple or slice of sql.Predicate"),
            }
            return self;
        }

        /// Execute the DELETE and return rows affected.
        pub fn Exec(self: *Self) !usize {
            if (info.policy) |p| {
                if (p.evalMutation(.delete, info.table_name) == .deny) {
                    return error.PrivacyDenied;
                }
            }
            for (self.hooks) |h| {
                if (h.op == .delete) {
                    if (h.before) |f| f(.delete, info.table_name);
                }
            }
            defer {
                for (self.hooks) |h| {
                    if (h.op == .delete) {
                        if (h.after) |f| f(.delete, info.table_name);
                    }
                }
            }

            var builder = sql.Delete(self.allocator, self.driver.dialect(), info.table_name);
            defer builder.deinit();

            for (self.predicates.items) |pred| {
                _ = builder.where(pred);
            }

            const q = try builder.query();
            const res = try self.driver.exec(q.sql, q.args);
            return res.rows_affected;
        }
    };
}

// ------------------------------------------------------------------
// Tests
// ------------------------------------------------------------------

test "Update builder basic" {
    const field = @import("../core/field.zig");
    const schema = @import("../core/schema.zig").Schema;
    const fromSchema = @import("graph.zig").fromSchema;

    const User = schema("User", .{
        .fields = &.{ field.String("name"), field.Int("age") },
    });

    const info = comptime fromSchema(User);
    const Upd = UpdateBuilder(info);

    var u = Upd.init(std.testing.allocator, undefined, &.{});
    defer u.deinit();

    _ = u.set("name", .{ .string = "bob" });
    try std.testing.expectEqual(@as(usize, 1), u.values.items.len);

    _ = u.Where(&.{sql.EQ("id", .{ .int = 1 })});
    try std.testing.expectEqual(@as(usize, 1), u.predicates.items.len);
}

test "Delete builder basic" {
    const field = @import("../core/field.zig");
    const schema = @import("../core/schema.zig").Schema;
    const fromSchema = @import("graph.zig").fromSchema;

    const User = schema("User", .{
        .fields = &.{ field.String("name"), field.Int("age") },
    });

    const info = comptime fromSchema(User);
    const Del = DeleteBuilder(info);

    var d = Del.init(std.testing.allocator, undefined, &.{});
    defer d.deinit();

    _ = d.Where(&.{sql.EQ("id", .{ .int = 1 })});
    try std.testing.expectEqual(@as(usize, 1), d.predicates.items.len);
}
