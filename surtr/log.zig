const std = @import("std");
const uefi = std.os.uefi;
const option = @import("option");

pub const default_log_option = std.Options{
    .log_level = switch (option.log_level) {
        .debug => .debug,
        .info => .info,
        .warn => .warn,
        .err => .err,
    },
    .logFn = log,
};

const Sto = uefi.protocol.SimpleTextOutput;

var status: uefi.Status = undefined;
var con_out: *Sto = undefined;

pub fn init(out: *Sto) void {
    con_out = out;
}

const Writer = std.io.GenericWriter(void, LogError, writerFunction);
const LogError = error{};

fn writerFunction(_: void, bytes: []const u8) LogError!usize {
    for (bytes) |b| {
        _ = con_out.outputString(&[_:0]u16{b}) catch unreachable;
    }
    return bytes.len;
}

fn log(comptime level: std.log.Level, comptime scope: @Type(.enum_literal), comptime fmt: []const u8, args: anytype) void {
    const level_str = comptime switch (level) {
        .debug => "[DEBUG]",
        .info => "[INFO]",
        .warn => "[WARN]",
        .err => "[ERROR]",
    };
    const scope_str = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";

    std.fmt.format(Writer{ .context = {} }, level_str ++ scope_str ++ fmt ++ "\r\n", args) catch unreachable;
}
