const std = @import("std");
const TypeInfo = @import("graph.zig").TypeInfo;
const EdgeInfo = @import("graph.zig").EdgeInfo;

fn findTypeInfo(comptime infos: []const TypeInfo, comptime name: []const u8) TypeInfo {
    for (infos) |info| {
        if (std.mem.eql(u8, info.name, name)) return info;
    }
    @compileError("TypeInfo not found: " ++ name);
}

fn toSnakeCase(name: []const u8) []const u8 {
    comptime {
        var result: []const u8 = "";
        for (name, 0..) |c, i| {
            if (std.ascii.isUpper(c) and i > 0) {
                result = result ++ "_";
            }
            result = result ++ &[_]u8{std.ascii.toLower(c)};
        }
        return result;
    }
}

/// Generate a light entity struct (fields only, no edges) from TypeInfo.
/// This breaks comptime recursion when edges reference each other.
pub fn LightEntity(comptime infos: []const TypeInfo, comptime info: TypeInfo) type {
    _ = infos;
    comptime {
        var fields: [info.fields.len]std.builtin.Type.StructField = undefined;
        for (info.fields, 0..) |f, i| {
            const FieldType = if (f.optional) ?f.zig_type else f.zig_type;
            fields[i] = .{
                .name = (f.name)[0..f.name.len :0],
                .type = FieldType,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = @alignOf(FieldType),
            };
        }
        return @Type(.{
            .@"struct" = .{
                .layout = .auto,
                .fields = &fields,
                .decls = &.{},
                .is_tuple = false,
            },
        });
    }
}

/// Generate an Edges struct for an entity.
/// Uses LightEntity for target types to avoid comptime recursion.
fn EdgesType(comptime infos: []const TypeInfo, comptime info: TypeInfo) type {
    comptime {
        if (info.edges.len == 0) {
            return struct {
                pub fn deinit(_: @This(), _: std.mem.Allocator) void {}
            };
        }
        var fields: [info.edges.len]std.builtin.Type.StructField = undefined;
        for (info.edges, 0..) |e, i| {
            const target_info = findTypeInfo(infos, e.target_name);
            const TargetEntity = LightEntity(infos, target_info);
            const FieldType = ?[]TargetEntity;
            const default_val: FieldType = null;
            fields[i] = .{
                .name = (e.name)[0..e.name.len :0],
                .type = FieldType,
                .default_value_ptr = &default_val,
                .is_comptime = false,
                .alignment = @alignOf(FieldType),
            };
        }
        return @Type(.{
            .@"struct" = .{
                .layout = .auto,
                .fields = &fields,
                .decls = &.{},
                .is_tuple = false,
            },
        });
    }
}

/// Generate an entity struct from TypeInfo.
pub fn Entity(comptime infos: []const TypeInfo, comptime info: TypeInfo) type {
    comptime {
        const ET = EdgesType(infos, info);
        const edges_default: ET = .{};
        var fields: [info.fields.len + 1]std.builtin.Type.StructField = undefined;
        for (info.fields, 0..) |f, i| {
            const FieldType = if (f.optional) ?f.zig_type else f.zig_type;
            fields[i] = .{
                .name = (f.name)[0..f.name.len :0],
                .type = FieldType,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = @alignOf(FieldType),
            };
        }
        fields[info.fields.len] = .{
            .name = "edges",
            .type = ET,
            .default_value_ptr = &edges_default,
            .is_comptime = false,
            .alignment = @alignOf(ET),
        };
        return @Type(.{
            .@"struct" = .{
                .layout = .auto,
                .fields = &fields,
                .decls = &.{},
                .is_tuple = false,
            },
        });
    }
}

// ------------------------------------------------------------------
// Tests
// ------------------------------------------------------------------

test "Entity struct generation" {
    const field = @import("../core/field.zig");
    const schema = @import("../core/schema.zig").Schema;
    const fromSchema = @import("graph.zig").fromSchema;

    const User = schema("User", .{
        .fields = &.{
            field.String("name"),
            field.Int("age"),
        },
    });

    const info = comptime fromSchema(User);
    const infos = &[_]TypeInfo{info};
    const UserEntity = comptime Entity(infos, info);

    var u: UserEntity = undefined;
    u.id = 1;
    u.name = "alice";
    u.age = 30;

    try std.testing.expectEqual(@as(i64, 1), u.id);
    try std.testing.expectEqualStrings("alice", u.name);
    try std.testing.expectEqual(@as(i64, 30), u.age);
}
