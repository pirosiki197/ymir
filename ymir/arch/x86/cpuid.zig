pub const Leaf = enum(u32) {
    maximum_input = 0x0,
    vers_and_feat_info = 0x1,
    ext_feature = 0x7,
    ext_enumeration = 0xD,
    ext_func = 0x8000000,
    ext_proc_signature = 0x80000001,
    _,

    pub fn from(rax: u64) Leaf {
        return @enumFromInt(rax);
    }
    pub fn query(self: Leaf, subleaf: ?u32) CpuidRegisters {
        return cpuid(@intFromEnum(self), subleaf orelse 0);
    }
};

const CpuidRegisters = struct {
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,
};

pub const FeatureInfoEcx = packed struct(u32) {
    _other_fields1: u5,
    /// Virtual Machine Extensions.
    vmx: bool = false,
    _other_fields2: u26,
};

fn cpuid(leaf: u32, subleaf: u32) CpuidRegisters {
    var eax: u32 = undefined;
    var ebx: u32 = undefined;
    var ecx: u32 = undefined;
    var edx: u32 = undefined;

    asm volatile (
        \\mov %[leaf], %%eax
        \\mov %[subleaf], %%ecx
        \\cpuid
        \\mov %%eax, %[eax]
        \\mov %%ebx, %[ebx]
        \\mov %%ecx, %[ecx]
        \\mov %%edx, %[edx]
        : [eax] "=r" (eax),
          [ebx] "=r" (ebx),
          [ecx] "=r" (ecx),
          [edx] "=r" (edx),
        : [leaf] "r" (leaf),
          [subleaf] "r" (subleaf),
        : .{ .rax = true, .rbx = true, .rcx = true, .rdx = true });

    return .{
        .eax = eax,
        .ebx = ebx,
        .ecx = ecx,
        .edx = edx,
    };
}
