const std = @import("std");
const am = @import("asm.zig");

pub const Phys = u64;
pub const Virt = u64;

const max_num_gdt = 0x10;

var gdt: [max_num_gdt]SegmentDescriptor align(16) = @splat(SegmentDescriptor.newNull());
const tss_unused: [4096]u8 align(4096) = @splat(0);

pub const kernel_ds_index: u16 = 0x01;
pub const kernel_cs_index: u16 = 0x02;
pub const kernel_tss_index: u16 = 0x03;

var gdtr = GdtRegister{
    .limit = @sizeOf(@TypeOf(gdt)) - 1,
    .base = undefined,
};

pub fn init() void {
    gdtr.base = &gdt;
    gdt[kernel_cs_index] = SegmentDescriptor.new(
        true,
        false,
        true,
        0,
        std.math.maxInt(u20),
        0,
        .kbyte,
    );
    gdt[kernel_ds_index] = SegmentDescriptor.new(
        true,
        false,
        false,
        0,
        std.math.maxInt(u20),
        0,
        .kbyte,
    );
    am.lgdt(@intFromPtr(&gdtr));
    setTss(@intFromPtr(&tss_unused));
    loadKernelDs();
    loadKernelCs();
    loadKernelTss();
}

pub const SegmentDescriptor = packed struct(u64) {
    /// Lower 16 bits of the segment limit.
    limit_low: u16,
    /// Lower 24 bits of the base address.
    base_low: u24,
    /// Segment is accessed.
    accessed: bool = true,
    /// Readable / Writable.
    rw: bool,
    /// Direction / Conforming.
    dc: bool,
    /// Executable.
    executable: bool,
    /// Descriptor type.
    desc_type: DescriptorType,
    /// Descriptor Privilege Level.
    dpl: u2,
    /// Segment present.
    present: bool = true,
    /// Upper 4 bits of the segment limit.
    limit_high: u4,
    /// Available for use by system software.
    avl: u1 = 0,
    /// 64-bit code segment.
    long: bool,
    /// Size flag.
    db: u1,
    /// Granularity.
    granularity: Granularity,
    /// Upper 8 bits of the base address.
    base_high: u8,

    pub fn newNull() SegmentDescriptor {
        return @bitCast(@as(u64, 0));
    }

    pub fn new(
        rw: bool,
        dc: bool,
        executable: bool,
        base: u32,
        limit: u20,
        dpl: u2,
        granularity: Granularity,
    ) SegmentDescriptor {
        return .{
            .rw = rw,
            .dc = dc,
            .executable = executable,
            .desc_type = .code_data,
            .base_low = @truncate(base),
            .base_high = @truncate(base >> 24),
            .limit_low = @truncate(limit),
            .limit_high = @truncate(limit >> 16),
            .dpl = dpl,
            .long = executable,
            .db = 0,
            .granularity = granularity,
        };
    }
};

pub const DescriptorType = enum(u1) {
    system = 0,
    code_data = 1,
};

pub const Granularity = enum(u1) {
    byte = 0,
    kbyte = 1,
};

const TssDescriptor = packed struct(u128) {
    /// Lower 16 bits of the segment limit.
    limit_low: u16,
    /// Lower 24 bits of the base address.
    base_low: u24,

    /// Type: TSS.
    type: u4 = 0b1001, // tss-avail
    /// Descriptor type: System.
    desc_type: DescriptorType = .system,
    /// Descriptor Privilege Level.
    dpl: u2 = 0,
    present: bool = true,

    /// Upper 4 bits of the segment limit.
    limit_high: u4,
    /// Available for use by system software.
    avl: u1 = 0,
    /// 64-bit code segment.
    long: bool = true,
    /// Size flag.
    db: u1 = 0,
    /// Granularity.
    granularity: Granularity = .kbyte,
    /// Upper 40 bits of the base address.
    base_high: u40,
    /// Reserved.
    _reserved: u32 = 0,

    /// Create a new 64-bit TSS descriptor.
    pub fn new(base: Virt, limit: u20) TssDescriptor {
        return TssDescriptor{
            .limit_low = @truncate(limit),
            .base_low = @truncate(base),
            .limit_high = @truncate(limit >> 16),
            .base_high = @truncate(base >> 24),
        };
    }
};

pub const SegmentSelector = packed struct(u16) {
    /// Requested Privilege Level.
    rpl: u2,
    /// Table Indicator.
    ti: u1 = 0,
    /// Index.
    index: u13,

    pub fn from(val: anytype) SegmentSelector {
        return @bitCast(@as(u16, @truncate(val)));
    }
};

const GdtRegister = packed struct {
    limit: u16,
    base: *[max_num_gdt]SegmentDescriptor,
};

fn setTss(tss: Virt) void {
    const desc = TssDescriptor.new(tss, std.math.maxInt(u20));
    @as(*TssDescriptor, @alignCast(@ptrCast(&gdt[kernel_tss_index]))).* = desc;
}

fn loadKernelTss() void {
    asm volatile (
        \\ mov %[kernel_tss], %%di
        \\ ltr %%di
        :
        : [kernel_tss] "n" (@as(u16, @bitCast(SegmentSelector{
            .rpl = 0,
            .index = kernel_tss_index,
          }))),
        : "di"
    );
}

fn loadKernelDs() void {
    asm volatile (
        \\ mov %[kernel_ds], %%di
        \\ mov %%di, %%ds
        \\ mov %%di, %%es
        \\ mov %%di, %%fs
        \\ mov %%di, %%gs
        \\ mov %%di, %%ss
        :
        : [kernel_ds] "n" (@as(u16, @bitCast(SegmentSelector{
            .rpl = 0,
            .index = kernel_ds_index,
          }))),
        : "di"
    );
}

fn loadKernelCs() void {
    asm volatile (
        \\ mov %[kernel_cs], %%rax
        \\ push %%rax
        \\ leaq next(%%rip), %%rax
        \\ pushq %%rax
        \\ lretq
        \\ next:
        \\
        :
        : [kernel_cs] "n" (@as(u16, @bitCast(SegmentSelector{
            .rpl = 0,
            .index = kernel_cs_index,
          }))),
    );
}
