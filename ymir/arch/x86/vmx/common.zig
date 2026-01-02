const std = @import("std");
const Allocator = std.mem.Allocator;

const mem = @import("ymir").mem;
const am = @import("../asm.zig");
const vmcs = @import("vmcs.zig");
const ept = @import("ept.zig");

pub const VmxError = error{
    VmxStatusUnavailable,
    VmxStatusAvailable,
    OutOfMemory,
    AlreadyMapped,
    InterruptFull,
};

pub fn mapGuest(host_pages: []u8, allocator: Allocator) VmxError!ept.Eptp {
    return ept.initEpt(
        0,
        mem.virt2phys(host_pages.ptr),
        host_pages.len,
        allocator,
    );
}

pub fn vmxtry(rflags: u64) VmxError!void {
    const flags: am.FlagsRegister = @bitCast(rflags);
    if (flags.cf) {
        return error.VmxStatusUnavailable;
    }
}

pub fn vmread(field: anytype) VmxError!u64 {
    var rflags: u64 = undefined;
    const ret = asm volatile (
        \\vmread %[field], %[ret]
        \\pushf
        \\popq %[rflags]
        : [ret] "={rax}" (-> u64),
          [rflags] "=r" (rflags),
        : [field] "r" (@as(u64, @intFromEnum(field))),
    );
    try vmxtry(rflags);
    return ret;
}

pub fn vmwrite(field: anytype, value: anytype) VmxError!void {
    const value_int = switch (@typeInfo(@TypeOf(value))) {
        .int, .comptime_int => @as(u64, value),
        .@"struct" => switch (@sizeOf(@TypeOf(value))) {
            1 => @as(u8, @bitCast(value)),
            2 => @as(u16, @bitCast(value)),
            4 => @as(u32, @bitCast(value)),
            8 => @as(u64, @bitCast(value)),
            else => @compileError("Unsupported type for vmwrite"),
        },
        .pointer => @as(u64, @intFromPtr(value)),
        else => @compileError("Unsupported type for vmwrite"),
    };

    const rflags = asm volatile (
        \\vmwrite %[value], %[field]
        \\pushf
        \\popq %[rflags]
        : [rflags] "=r" (-> u64),
        : [value] "r" (@as(u64, value_int)),
          [field] "r" (@as(u64, @intFromEnum(field))),
    );
    try vmxtry(rflags);
}

pub const InstructionError = enum(u32) {
    error_not_available = 0,
    vmcall_in_vmxroot = 1,
    vmclear_invalid_phys = 2,
    vmclear_vmxonptr = 3,
    vmlaunch_nonclear_vmcs = 4,
    vmresume_nonlaunched_vmcs = 5,
    vmresume_after_vmxoff = 6,
    vmentry_invalid_ctrl = 7,
    vmentry_invalid_host_state = 8,
    vmptrld_invalid_phys = 9,
    vmptrld_vmxonp = 10,
    vmptrld_incorrect_rev = 11,
    vmrw_unsupported_component = 12,
    vmw_ro_component = 13,
    vmxon_in_vmxroot = 15,
    vmentry_invalid_exec_ctrl = 16,
    vmentry_nonlaunched_exec_ctrl = 17,
    vmentry_exec_vmcsptr = 18,
    vmcall_nonclear_vmcs = 19,
    vmcall_invalid_exitctl = 20,
    vmcall_incorrect_msgrev = 22,
    vmxoff_dualmonitor = 23,
    vmcall_invalid_smm = 24,
    vmentry_invalid_execctrl = 25,
    vmentry_events_blocked = 26,
    invalid_invept = 28,

    /// Get an instruction error number from VMCS.
    pub fn load() VmxError!InstructionError {
        return @enumFromInt(@as(u32, @truncate(try vmread(vmcs.ro.vminstruction_error))));
    }
};

pub const SegmentRights = packed struct(u32) {
    const gdt = @import("../gdt.zig");

    accessed: bool = true,
    rw: bool,
    dc: bool,
    executable: bool,
    desc_type: gdt.DescriptorType,
    dpl: u2,
    present: bool = true,
    _reserved1: u4 = 0,
    avl: bool = false,
    long: bool = false,
    db: u1,
    granularity: gdt.Granularity,
    unusable: bool = false,
    _reserved2: u15 = 0,
};

pub const GuestRegisters = extern struct {
    rax: u64,
    rcx: u64,
    rdx: u64,
    rbx: u64,
    rbp: u64,
    rsi: u64,
    rdi: u64,
    r8: u64,
    r9: u64,
    r10: u64,
    r11: u64,
    r12: u64,
    r13: u64,
    r14: u64,
    r15: u64,
    // Align to 16 bytes, otherwise movaps would cause #GP.
    xmm0: u128 align(16),
    xmm1: u128 align(16),
    xmm2: u128 align(16),
    xmm3: u128 align(16),
    xmm4: u128 align(16),
    xmm5: u128 align(16),
    xmm6: u128 align(16),
    xmm7: u128 align(16),
};

pub const qual = struct {
    pub const QualCr = packed struct(u64) {
        index: u4,
        access_type: AccessType,
        lmsw_type: LmswOperandType,
        _reserved1: u1,
        reg: Register,
        _reserved2: u4,
        lmsw_source: u16,
        _reserved3: u32,

        const AccessType = enum(u2) {
            mov_to = 0,
            mov_from = 1,
            clts = 2,
            lmsw = 3,
        };
        const LmswOperandType = enum(u1) {
            reg = 0,
            mem = 1,
        };
        const Register = enum(u4) {
            rax = 0,
            rcx = 1,
            rdx = 2,
            rbx = 3,
            rsp = 4,
            rbp = 5,
            rsi = 6,
            rdi = 7,
            r8 = 8,
            r9 = 9,
            r10 = 10,
            r11 = 11,
            r12 = 12,
            r13 = 13,
            r14 = 14,
            r15 = 15,
        };
    };
    pub const QualIo = packed struct(u64) {
        /// Size of access.
        size: Size,
        /// Direction of the attempted access.
        direction: Direction,
        /// String instruction.
        string: bool,
        /// Rep prefix.
        rep: bool,
        /// Operand encoding.
        operand_encoding: OperandEncoding,
        /// Not used.
        _reserved2: u9,
        /// Port number.
        port: u16,
        /// Not used.
        _reserved3: u32,

        const Size = enum(u3) {
            /// Byte.
            byte = 0,
            /// Word.
            word = 1,
            /// Dword.
            dword = 3,
        };

        const Direction = enum(u1) {
            out = 0,
            in = 1,
        };

        const OperandEncoding = enum(u1) {
            /// I/O instruction uses DX register as port number.
            dx = 0,
            /// I/O instruction uses immediate value as port number.
            imm = 1,
        };
    };
};

pub const EntryIntrInfo = packed struct(u32) {
    vector: u8,
    type: Type,
    ec_available: bool,
    _notused: u19 = 0,
    valid: bool,

    const Type = enum(u3) {
        external = 0,
        _unused1 = 1,
        nmi = 2,
        hw = 3,
        _unused2 = 4,
        priviledged_sw = 5,
        exception = 6,
        _unused3 = 7,
    };

    const Kind = enum {
        entry,
        exit,
    };
};
