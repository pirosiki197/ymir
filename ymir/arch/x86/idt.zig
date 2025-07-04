const std = @import("std");
const gdt = @import("gdt.zig");
const am = @import("asm.zig");

pub const max_num_gates = 256;
var idt: [max_num_gates]GateDescriptor align(4096) = @splat(std.mem.zeroes(GateDescriptor));

var idtr = IdtRegister{
    .limit = @sizeOf(@TypeOf(idt)) - 1,
    .base = undefined,
};

pub fn init() void {
    idtr.base = &idt;
    am.lidt(@intFromPtr(&idtr));
}

/// Entry in the Interrupt Descriptor Table.
pub const GateDescriptor = packed struct(u128) {
    /// Lower 16 bits of the offset to the ISR.
    offset_low: u16,
    /// Segment Selector that must point to a valid code segment in the GDT.
    seg_selector: u16,
    /// Interrupt Stack Table. Not used.
    ist: u3 = 0,
    /// Reserved.
    _reserved1: u5 = 0,
    /// Gate Type.
    gate_type: GateType,
    /// Reserved.
    _reserved2: u1 = 0,
    /// Descriptor Privilege Level is the required CPL to call the ISR via the INT inst.
    /// Hardware interrupts ignore this field.
    dpl: u2,
    /// Present flag. Must be 1.
    present: bool = true,
    /// Middle 16 bits of the offset to the ISR.
    offset_middle: u16,
    /// Higher 32 bits of the offset to the ISR.
    offset_high: u32,
    /// Reserved.
    _reserved3: u32 = 0,

    pub fn offset(self: GateDescriptor) u64 {
        return @as(u64, self.offset_high) << 32 | @as(u64, self.offset_middle) << 16 | @as(u64, self.offset_low);
    }
};

pub const GateType = enum(u4) {
    Invalid = 0b0000,
    Interrupt64 = 0b1110,
    Trap64 = 0b1111,
};

const IdtRegister = packed struct {
    limit: u16,
    base: *[max_num_gates]GateDescriptor,
};

pub const Isr = fn () callconv(.naked) void;

pub fn setGate(
    index: usize,
    gate_type: GateType,
    offset: Isr,
) void {
    idt[index] = GateDescriptor{
        .offset_low = @truncate(@intFromPtr(&offset)),
        .seg_selector = gdt.kernel_cs_index << 3,
        .gate_type = gate_type,
        .offset_middle = @truncate(@as(u64, @intFromPtr(&offset)) >> 16),
        .offset_high = @truncate(@as(u64, @intFromPtr(&offset)) >> 32),
        .dpl = 0,
    };
}
