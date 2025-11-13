const std = @import("std");

const ymir = @import("ymir");
const bits = ymir.bits;
const mem = ymir.mem;

const vmx = @import("vmx/common.zig");
const VmxError = vmx.VmxError;
const vmxerr = vmx.vmxtry;

pub inline fn inb(port: u16) u8 {
    return asm volatile (
        \\inb %[port], %[ret]
        : [ret] "={al}" (-> u8),
        : [port] "{dx}" (port),
    );
}
pub inline fn outb(value: u8, port: u16) void {
    asm volatile (
        \\outb %[value], %[port]
        :
        : [value] "{al}" (value),
          [port] "{dx}" (port),
    );
}

pub inline fn relax() void {
    asm volatile (
        \\rep
        \\nop
    );
}

pub inline fn lgdt(gdtr: u64) void {
    asm volatile (
        \\ lgdt (%[gdtr])
        :
        : [gdtr] "r" (gdtr),
    );
}

pub inline fn lidt(idtr: u64) void {
    asm volatile (
        \\ lidt (%[idtr])
        :
        : [idtr] "r" (idtr),
    );
}

pub inline fn cli() void {
    asm volatile ("cli");
}

pub inline fn sti() void {
    asm volatile ("sti");
}

pub const Cr4 = packed struct(u64) {
    _other_fields1: u13,
    vmxe: bool,
    _other_fields2: u50,
};

pub inline fn readCr0() u64 {
    var cr0: u64 = undefined;
    asm volatile (
        \\mov %%cr0, %[cr0]
        : [cr0] "=r" (cr0),
    );
    return cr0;
}

pub inline fn readCr3() u64 {
    var cr3: u64 = undefined;
    asm volatile (
        \\ mov %%cr3, %[cr3]
        : [cr3] "=r" (cr3),
    );
    return cr3;
}

pub inline fn readCr4() Cr4 {
    var cr4: u64 = undefined;
    asm volatile (
        \\mov %%cr4, %[cr4]
        : [cr4] "=r" (cr4),
    );
    return @bitCast(cr4);
}

pub inline fn loadCr0(cr0: u64) void {
    asm volatile (
        \\mov %[cr0], %%cr0
        :
        : [cr0] "r" (cr0),
    );
}

pub inline fn loadCr3(cr3: u64) void {
    asm volatile (
        \\ mov %[cr3], %%cr3
        :
        : [cr3] "r" (cr3),
    );
}

pub inline fn loadCr4(cr4: u64) void {
    asm volatile (
        \\ mov %[cr4], %%cr4
        :
        : [cr4] "r" (cr4),
    );
}

pub const Msr = enum(u32) {
    feature_control = 0x003A,

    vmx_basic = 0x0480,

    vmx_cr0_fixed0 = 0x486,
    vmx_cr0_fixed1 = 0x487,
    vmx_cr4_fixed0 = 0x488,
    vmx_cr4_fixed1 = 0x489,

    _,
};

pub const MsrFeatureControl = packed struct(u64) {
    /// Lock bit
    lock: bool,
    /// VMX in SMX (Safer Mode Extensions) operation
    vmx_in_smx: bool,
    /// VMX outside SMX operation
    vmx_outside_smx: bool,
    _other_fields: u61,
};

pub fn readMsr(msr: Msr) u64 {
    var eax: u32 = undefined;
    var edx: u32 = undefined;
    asm volatile (
        \\rdmsr
        : [eax] "={eax}" (eax),
          [edx] "={edx}" (edx),
        : [msr] "{ecx}" (@intFromEnum(msr)),
    );
    return bits.concat(u64, edx, eax);
}

pub fn writeMsr(msr: Msr, value: u64) void {
    asm volatile (
        \\wrmsr
        :
        : [msr] "{ecx}" (@intFromEnum(msr)),
          [eax] "{eax}" (@as(u32, @truncate(value))),
          [edx] "{edx}" (@as(u32, @truncate(value >> 32))),
    );
}

pub fn readMsrVmxBasic() MsrVmxBasic {
    const val = readMsr(.vmx_basic);
    return @bitCast(val);
}

pub const MsrVmxBasic = packed struct(u64) {
    vmcs_revision_id: u31,
    _zero: u1 = 0,
    vmxon_region_size: u16,
    _reserved1: u7,
    true_control: bool,
    _reserved2: u8,
};

pub inline fn vmxon(vmxon_region: mem.Phys) VmxError!void {
    var rflags: u64 = undefined;
    asm volatile (
        \\vmxon (%[vmxon_phys])
        \\pushf
        \\popq %[rflags]
        : [rflags] "=r" (rflags),
        : [vmxon_phys] "r" (&vmxon_region),
        : .{ .cc = true, .memory = true });
    try vmxerr(rflags);
}

pub const FlagsRegister = packed struct(u64) {
    /// Carry flag
    cf: bool,
    _reserved0: u1 = 1,
    _other_fields: u4,
    /// Zero flag
    zf: bool,
    _other_fields2: u57,

    pub fn new() FlagsRegister {
        var res = std.mem.zeroes(FlagsRegister);
        res._reserved0 = 1;
        return res;
    }
};
