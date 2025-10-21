pub const serial = @import("serial.zig");
const am = @import("asm.zig");
pub const gdt = @import("gdt.zig");
pub const itr = @import("interrupt.zig");
pub const page = @import("page.zig");
pub const relax = am.relax;
