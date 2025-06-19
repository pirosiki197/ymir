pub fn tobit(T: type, nth: anytype) T {
    const val = switch (@typeInfo(@TypeOf(nth))) {
        .int, .comptime_int => nth,
        .@"enum" => @intFromEnum(nth),
        else => @compileError("tobit: invalid type"),
    };
    return @as(T, 1) << @intCast(val);
}

pub inline fn isset(val: anytype, nth: anytype) bool {
    const int_nth = switch (@typeInfo(@TypeOf(nth))) {
        .int, .comptime_int => nth,
        .@"enum" => @intFromEnum(nth),
        else => @compileError("isset: invalid type"),
    };
    return ((val >> @intCast(int_nth)) & 1) != 0;
}
pub inline fn concat(T: type, a: anytype, b: @TypeOf(a)) T {
    const U = @TypeOf(a);
    const width_T = @typeInfo(T).int.bits;
    const width_U = switch (@typeInfo(U)) {
        .int => |t| t.bits,
        .comptime_int => width_T / 2,
        else => @compileError("concat: invalid type."),
    };
    if (width_T != width_U * 2) @compileError("concat: invalid type.");
    return (@as(T, a) << width_U | @as(T, b));
}

const testing = @import("std").testing;

test "tobit" {
    try testing.expectEqual(0b0000_0001, tobit(u8, 0));
    try testing.expectEqual(0b0001_0000, tobit(u8, 4));
    try testing.expectEqual(0b1000_0000, tobit(u8, 7));
}

test "isset" {
    try testing.expectEqual(true, isset(0b0000_0001, 0));
    try testing.expectEqual(false, isset(0b1100_0011, 2));
}

test "concat" {
    try testing.expectEqual(@as(u8, 0b1100_0101), concat(u8, @as(u4, 0b1100), @as(u4, 0b0101)));
}
