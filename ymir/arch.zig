const arch = @import("arch/x86/arch.zig");
pub const serial = arch.serial;
pub const gdt = arch.gdt;
pub const intr = arch.intr;
pub const page = arch.page;
pub const pic = arch.pic;
pub const relax = arch.relax;
pub const disableIntr = arch.disableIntr;
