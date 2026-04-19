const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut();
    try stdout.writeAll(
        \\zent CLI - Zig Entity Framework Tool
        \\
        \\Usage:
        \\  zent help, --help, -h              Show this help message
        \\  zent version, --version, -v        Show version
        \\
        \\Note: SQL schema generation coming soon!
        \\
    );
}
