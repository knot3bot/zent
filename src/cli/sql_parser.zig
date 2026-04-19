const std = @import("std");

/// Represents a parsed SQL column.
pub const Column = struct {
    name: []const u8,
    sql_type: []const u8,
    not_null: bool = false,
    primary_key: bool = false,
    default: ?[]const u8 = null,
    auto_increment: bool = false,
};

/// Represents a parsed SQL table.
pub const Table = struct {
    name: []const u8,
    columns: std.ArrayList(Column),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Table {
        return .{
            .name = name,
            .columns = std.ArrayList(Column).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Table) void {
        self.columns.deinit();
    }

    pub fn addColumn(self: *Table, col: Column) !void {
        try self.columns.append(col);
    }
};

/// SQL schema parser.
pub const Parser = struct {
    allocator: std.mem.Allocator,
    tables: std.ArrayList(Table),
    current_pos: usize = 0,
    input: []const u8,

    pub fn init(allocator: std.mem.Allocator) Parser {
        return .{
            .allocator = allocator,
            .tables = std.ArrayList(Table).init(allocator),
            .input = "",
        };
    }

    pub fn deinit(self: *Parser) void {
        for (self.tables.items) |*table| {
            table.deinit();
        }
        self.tables.deinit();
    }

    /// Parse SQL schema from a string.
    pub fn parse(self: *Parser, sql: []const u8) ![]const Table {
        self.input = sql;
        self.current_pos = 0;

        // Skip whitespace and comments
        self.skipWhitespaceAndComments();

        while (self.current_pos < self.input.len) {
            if (self.matchKeyword("CREATE")) {
                try self.parseCreateTable();
            } else {
                self.skipToNextStatement();
            }
            self.skipWhitespaceAndComments();
        }

        return self.tables.items;
    }

    fn skipWhitespaceAndComments(self: *Parser) void {
        while (self.current_pos < self.input.len) {
            const c = self.input[self.current_pos];
            if (std.ascii.isWhitespace(c)) {
                self.current_pos += 1;
            } else if (self.current_pos + 1 < self.input.len and
                self.input[self.current_pos] == '-' and
                self.input[self.current_pos + 1] == '-')
            {
                self.skipLineComment();
            } else if (self.current_pos + 1 < self.input.len and
                self.input[self.current_pos] == '/' and
                self.input[self.current_pos + 1] == '*')
            {
                self.skipBlockComment();
            } else {
                break;
            }
        }
    }

    fn skipLineComment(self: *Parser) void {
        while (self.current_pos < self.input.len and self.input[self.current_pos] != '\n') {
            self.current_pos += 1;
        }
    }

    fn skipBlockComment(self: *Parser) void {
        self.current_pos += 2; // Skip /*
        while (self.current_pos + 1 < self.input.len) {
            if (self.input[self.current_pos] == '*' and self.input[self.current_pos + 1] == '/') {
                self.current_pos += 2;
                break;
            }
            self.current_pos += 1;
        }
    }

    fn skipToNextStatement(self: *Parser) void {
        while (self.current_pos < self.input.len) {
            if (self.input[self.current_pos] == ';') {
                self.current_pos += 1;
                break;
            }
            self.current_pos += 1;
        }
    }

    fn matchKeyword(self: *Parser, keyword: []const u8) bool {
        self.skipWhitespaceAndComments();

        if (self.current_pos + keyword.len > self.input.len) return false;

        const slice = self.input[self.current_pos .. self.current_pos + keyword.len];
        if (std.ascii.eqlIgnoreCase(slice, keyword)) {
            self.current_pos += keyword.len;
            return true;
        }
        return false;
    }

    fn parseCreateTable(self: *Parser) !void {
        if (!self.matchKeyword("TABLE")) return;

        self.skipWhitespaceAndComments();

        const table_name_start = self.current_pos;
        while (self.current_pos < self.input.len and
            (std.ascii.isAlphanumeric(self.input[self.current_pos]) or
            self.input[self.current_pos] == '_' or
            self.input[self.current_pos] == '"' or
            self.input[self.current_pos] == '`'))
        {
            self.current_pos += 1;
        }

        var table_name = self.input[table_name_start..self.current_pos];
        table_name = std.mem.trim(u8, table_name, "\"`");

        var table = Table.init(self.allocator, table_name);
        errdefer table.deinit();

        self.skipWhitespaceAndComments();

        if (self.current_pos < self.input.len and self.input[self.current_pos] == '(') {
            self.current_pos += 1;
            try self.parseColumns(&table);
        }

        try self.tables.append(table);
    }

    fn parseColumns(self: *Parser, table: *Table) !void {
        self.skipWhitespaceAndComments();

        while (self.current_pos < self.input.len and self.input[self.current_pos] != ')') {
            if (self.matchKeyword("PRIMARY") or
                self.matchKeyword("FOREIGN") or
                self.matchKeyword("UNIQUE") or
                self.matchKeyword("KEY") or
                self.matchKeyword("INDEX") or
                self.matchKeyword("CONSTRAINT"))
            {
                self.skipToNextColumn();
            } else {
                try self.parseColumn(table);
            }

            self.skipWhitespaceAndComments();
            if (self.current_pos < self.input.len and self.input[self.current_pos] == ',') {
                self.current_pos += 1;
            }
            self.skipWhitespaceAndComments();
        }

        if (self.current_pos < self.input.len and self.input[self.current_pos] == ')') {
            self.current_pos += 1;
        }
    }

    fn skipToNextColumn(self: *Parser) void {
        var depth: usize = 0;
        while (self.current_pos < self.input.len) {
            const c = self.input[self.current_pos];
            if (c == '(') {
                depth += 1;
            } else if (c == ')') {
                if (depth == 0) break;
                depth -= 1;
            } else if (c == ',' and depth == 0) {
                break;
            }
            self.current_pos += 1;
        }
    }

    fn parseColumn(self: *Parser, table: *Table) !void {
        const col_name_start = self.current_pos;
        while (self.current_pos < self.input.len and
            (std.ascii.isAlphanumeric(self.input[self.current_pos]) or
            self.input[self.current_pos] == '_' or
            self.input[self.current_pos] == '"' or
            self.input[self.current_pos] == '`'))
        {
            self.current_pos += 1;
        }

        var col_name = self.input[col_name_start..self.current_pos];
        col_name = std.mem.trim(u8, col_name, "\"`");

        self.skipWhitespaceAndComments();

        const type_start = self.current_pos;
        while (self.current_pos < self.input.len and
            (std.ascii.isAlphanumeric(self.input[self.current_pos]) or
            self.input[self.current_pos] == '(' or
            self.input[self.current_pos] == ')' or
            self.input[self.current_pos] == ',' or
            self.input[self.current_pos] == ' '))
        {
            if (self.input[self.current_pos] == '(') {
                var depth: usize = 1;
                self.current_pos += 1;
                while (self.current_pos < self.input.len and depth > 0) {
                    if (self.input[self.current_pos] == '(') depth += 1;
                    if (self.input[self.current_pos] == ')') depth -= 1;
                    self.current_pos += 1;
                }
            } else if (self.input[self.current_pos] == ',' or self.input[self.current_pos] == ')') {
                break;
            } else {
                self.current_pos += 1;
            }
        }

        var col_type = self.input[type_start..self.current_pos];
        col_type = std.mem.trim(u8, col_type, " \t\n\r");

        var column = Column{
            .name = col_name,
            .sql_type = col_type,
        };

        self.skipWhitespaceAndComments();
        while (self.current_pos < self.input.len and
            self.input[self.current_pos] != ',' and
            self.input[self.current_pos] != ')')
        {
            if (self.matchKeyword("NOT")) {
                self.skipWhitespaceAndComments();
                if (self.matchKeyword("NULL")) {
                    column.not_null = true;
                }
            } else if (self.matchKeyword("NULL")) {
                column.not_null = false;
            } else if (self.matchKeyword("PRIMARY")) {
                self.skipWhitespaceAndComments();
                if (self.matchKeyword("KEY")) {
                    column.primary_key = true;
                }
            } else if (self.matchKeyword("AUTO_INCREMENT") or
                self.matchKeyword("AUTOINCREMENT") or
                self.matchKeyword("SERIAL"))
            {
                column.auto_increment = true;
            } else if (self.matchKeyword("DEFAULT")) {
                self.skipWhitespaceAndComments();
                const default_start = self.current_pos;
                var depth: usize = 0;
                while (self.current_pos < self.input.len) {
                    const c = self.input[self.current_pos];
                    if (c == '(') depth += 1;
                    if (c == ')') {
                        if (depth == 0) break;
                        depth -= 1;
                    }
                    if ((c == ',' or c == ')') and depth == 0) break;
                    self.current_pos += 1;
                }
                column.default = self.input[default_start..self.current_pos];
            } else {
                self.current_pos += 1;
            }
            self.skipWhitespaceAndComments();
        }

        try table.addColumn(column);
    }
};

test "Basic SQL parsing" {
    const allocator = std.testing.allocator;
    var parser = Parser.init(allocator);
    defer parser.deinit();

    const sql =
        \\CREATE TABLE users (
        \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\    name TEXT NOT NULL,
        \\    age INTEGER,
        \\    created_at DATETIME
        \\);
    ;

    const tables = try parser.parse(sql);
    try std.testing.expectEqual(@as(usize, 1), tables.len);
    try std.testing.expectEqualStrings("users", tables[0].name);
    try std.testing.expectEqual(@as(usize, 4), tables[0].columns.items.len);
}
