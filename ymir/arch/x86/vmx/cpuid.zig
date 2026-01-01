const std = @import("std");
const log = std.log.scoped(.cpuid);
const arch = @import("../arch.zig");

const cpuid = arch.cpuid;
const Leaf = cpuid.Leaf;
const VmxError = @import("common.zig").VmxError;
const Vcpu = @import("vcpu.zig").Vcpu;

const feature_info_ecx = cpuid.FeatureInfoEcx{
    .pcid = true,
};
const feature_info_edx = cpuid.FeatureInfoEdx{
    .fpu = true,
    .vme = true,
    .de = true,
    .pse = true,
    .msr = true,
    .pae = true,
    .cx8 = true,
    .sep = true,
    .pge = true,
    .cmov = true,
    .pse36 = true,
    .acpi = false,
    .fxsr = true,
    .sse = true,
    .sse2 = true,
};
const ext_feature0_ebx = cpuid.ExtFeatureEbx0{
    .fsgsbase = false,
    .smep = true,
    .invpcid = true,
    .smap = true,
};

pub fn handleCpuidExit(vcpu: *Vcpu) VmxError!void {
    const regs = &vcpu.guest_regs;
    switch (Leaf.from(regs.rax)) {
        .maximum_input => {
            setValue(&regs.rax, 0x20);
            setValue(&regs.rbx, 0x72_69_6D_59); // Ymir
            setValue(&regs.rcx, 0x72_69_6D_59); // Ymir
            setValue(&regs.rdx, 0x72_69_6D_59); // Ymir
        },
        .vers_and_feat_info => {
            const orig = Leaf.query(.vers_and_feat_info, null);
            setValue(&regs.rax, orig.eax);
            setValue(&regs.rbx, orig.ebx);
            setValue(&regs.rcx, @as(u32, @bitCast(feature_info_ecx)));
            setValue(&regs.rdx, @as(u32, @bitCast(feature_info_edx)));
        },
        .ext_feature => {
            switch (regs.rcx) {
                0 => {
                    setValue(&regs.rax, 1);
                    setValue(&regs.rbx, @as(u32, @bitCast(ext_feature0_ebx)));
                    setValue(&regs.rcx, 0);
                    setValue(&regs.rdx, 0);
                },
                1, 2 => invalid(vcpu),
                else => {
                    log.err("Unhandled CPUID: Leaf=0x{X:0>8}, Sub=0x{X:0>8}", .{ regs.rax, regs.rcx });
                    vcpu.abort();
                },
            }
        },
        .ext_enumeration => {
            switch (regs.rcx) {
                1 => invalid(vcpu),
                else => {
                    log.err("Unhandled CPUID: Leaf={X:0>8}, Sub={X:0>8}", .{ regs.rax, regs.rcx });
                    vcpu.abort();
                },
            }
        },
        .ext_func => {
            setValue(&regs.rax, 0x8000_0000 + 1);
            setValue(&regs.rbx, 0);
            setValue(&regs.rcx, 0);
            setValue(&regs.rdx, 0);
        },
        .ext_proc_signature => {
            const orig = Leaf.ext_proc_signature.query(null);
            setValue(&regs.rax, 0);
            setValue(&regs.rbx, 0);
            setValue(&regs.rcx, orig.ecx);
            setValue(&regs.rdx, orig.edx);
        },
        _ => {
            log.warn("Unhandled CPUID: Leaf=0x{X:0>8}, Sub=0x{X:0>8}", .{ regs.rax, regs.rcx });
            invalid(vcpu);
        },
    }
}

fn invalid(vcpu: *Vcpu) void {
    const gregs = &vcpu.guest_regs;
    setValue(&gregs.rax, 0);
    setValue(&gregs.rbx, 0);
    setValue(&gregs.rcx, 0);
    setValue(&gregs.rdx, 0);
}

inline fn setValue(reg: *u64, val: u64) void {
    @as(*u32, @ptrCast(reg)).* = @as(u32, @truncate(val));
}
