const std = @import("std");
const stdlog = std.log;
const option = @import("option");
const Serial = @import("ymir").serial.Serial;

const LogError = error{};

const Writer = std.io.GenericWriter(void, LogError, write);

pub const default_log_options = std.Options{
    .log_level = switch (option.log_level) {
        .debug => .debug,
        .info => .info,
        .warn => .warn,
        .err => .err,
    },
    .logFn = log,
};

var serial: Serial = undefined;

pub fn init(ser: Serial) void {
    serial = ser;
}

fn log(comptime level: stdlog.Level, comptime scope: @Type(.enum_literal), comptime fmt: []const u8, args: anytype) void {
    const level_str = comptime switch (level) {
        .debug => "[DEBUG]",
        .info => "[INFO]",
        .warn => "[WARN]",
        .err => "[ERROR]",
    };
    const scope_str = std.fmt.comptimePrint("{s} | ", .{@tagName(scope)});

    std.fmt.format(
        Writer{ .context = {} },
        level_str ++ " " ++ scope_str ++ fmt ++ "\n",
        args,
    ) catch unreachable;
}

fn write(_: void, bytes: []const u8) LogError!usize {
    serial.writeString(bytes);
    return bytes.len;
}
