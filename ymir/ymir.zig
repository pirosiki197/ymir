pub const serial = @import("serial.zig");
pub const arch = @import("arch.zig");
pub const bits = @import("bits.zig");
pub const klog = @import("log.zig");
pub const mem = @import("mem/mem.zig");

const gib = 1024 * 1024 * 1024;
pub const direct_map_base = 0xFFFF_8880_0000_0000;
pub const direct_map_size = 512 * gib;
pub const kernel_base = 0xFFFF_FFFF_8000_0000;

pub fn endlessHalt() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}

const testing = @import("std").testing;
test {
    testing.refAllDeclsRecursive(@This());
}
