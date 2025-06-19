const serial = @import("ymir").arch.serial;
pub const initSerial = serial.initSerial;
const writeByte = serial.writeByte;

pub const Serial = struct {
    const Self = @This();
    const WriteFn = *const fn (u8) void;
    const ReadFn = *const fn () ?u8;

    _write_fn: WriteFn = undefined,
    _read_fn: ReadFn = undefined,

    pub fn init() Serial {
        var s = Serial{};
        serial.initSerial(&s, .com1, 115200);
        return s;
    }

    pub fn write(self: Self, b: u8) void {
        self._write_fn(b);
    }

    pub fn writeString(self: Self, s: []const u8) void {
        for (s) |c| {
            self._write_fn(c);
        }
    }
};
