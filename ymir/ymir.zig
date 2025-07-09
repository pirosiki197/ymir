pub const serial = @import("serial.zig");
pub const arch = @import("arch.zig");
pub const bits = @import("bits.zig");
pub const klog = @import("log.zig");
pub const mem = @import("mem/mem.zig");

pub fn endlessHalt() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}

const testing = @import("std").testing;
test {
    testing.refAllDeclsRecursive(@This());
}
