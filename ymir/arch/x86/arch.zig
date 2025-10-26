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
