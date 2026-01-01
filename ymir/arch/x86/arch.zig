pub const cpuid = @import("cpuid.zig");
pub const serial = @import("serial.zig");
const am = @import("asm.zig");
pub const gdt = @import("gdt.zig");
pub const intr = @import("interrupt.zig");
pub const page = @import("page.zig");
pub const pic = @import("pic.zig");

pub const relax = am.relax;

pub inline fn disableIntr() void {
    am.cli();
}

pub fn getCpuVendorId() [12]u8 {
    var ret: [12]u8 = undefined;
    const regs = cpuid.Leaf.query(.maximum_input, null);

    for ([_]u32{ regs.ebx, regs.edx, regs.ecx }, 0..) |reg, i| {
        for (0..4) |j| {
            const b: usize = reg >> @truncate(j * 8);
            ret[i * 4 + j] = @truncate(b);
        }
    }
    return ret;
}

pub fn isVmxSupported() bool {
    const regs = cpuid.Leaf.query(.vers_and_feat_info, null);
    const ecx: cpuid.FeatureInfoEcx = @bitCast(regs.ecx);
    if (!ecx.vmx) return false;

    var msr_fctrl: am.MsrFeatureControl = @bitCast(am.readMsr(.feature_control));
    if (msr_fctrl.vmx_outside_smx) return true;

    if (msr_fctrl.lock) @panic("IA32_FEATURE_CONTROL is locked while VMX outside SMX is disabled");
    msr_fctrl.vmx_outside_smx = true;
    msr_fctrl.lock = true;
    am.writeMsr(.feature_control, @bitCast(msr_fctrl));
    msr_fctrl = @bitCast(am.readMsr(.feature_control));
    if (!msr_fctrl.vmx_outside_smx) return false;

    return true;
}
