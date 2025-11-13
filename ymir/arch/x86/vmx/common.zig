const am = @import("../asm.zig");

pub const VmxError = error{
    VmxStatusUnavailable,
    VmxStatusAvailable,
    OutOfMemory,
};

pub fn vmxtry(rflags: u64) VmxError!void {
    const flags: am.FlagsRegister = @bitCast(rflags);
    if (flags.cf) {
        return error.VmxStatusUnavailable;
    }
}
