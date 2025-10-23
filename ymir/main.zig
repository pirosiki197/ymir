const surtr = @import("surtr");
const ymir = @import("ymir");
const arch = ymir.arch;
const Serial = ymir.serial.Serial;
const klog = ymir.klog;
const log = @import("std").log.scoped(.main);
const mem = ymir.mem;
pub const std_options = klog.default_log_options;

extern const __stackguard_lower: [*]const u8;

pub const panic = ymir.panic.panic_fn;

export fn kernelEntry() callconv(.naked) noreturn {
    asm volatile (
        \\ movq %[new_stack], %%rsp
        \\ call kernelTrampoline
        :
        : [new_stack] "r" (@intFromPtr(&__stackguard_lower) - 0x10),
    );
}

export fn kernelTrampoline(boot_info: surtr.BootInfo) callconv(.{ .x86_64_win = .{} }) noreturn {
    kernelMain(boot_info) catch {
        @panic("Exiting...");
    };

    unreachable;
}

fn kernelMain(boot_info: surtr.BootInfo) !void {
    validateBootInfo(boot_info) catch {
        log.err("Invalid boot info.", .{});
        return error.InvalidBootInfo;
    };

    const serial = Serial.init();
    klog.init(serial);
    log.info("Hello, world!", .{});
    arch.gdt.init();
    log.info("Initialized GDT.", .{});
    arch.itr.init();
    log.info("Initialized IDT.", .{});
    mem.initPageAllocator(boot_info.memory_map);
    log.info("Initialized page allocator.", .{});
    const page_allocator = mem.page_allocator;
    log.info("Reconstructing memory mapping...", .{});
    try mem.reconstructMapping(mem.page_allocator);

    const array = try page_allocator.alloc(u32, 4);
    log.info("Memory allocated @ {*}", .{array.ptr});
    page_allocator.free(array);

    while (true) asm volatile ("hlt");
}

fn validateBootInfo(boot_info: surtr.BootInfo) !void {
    if (boot_info.magic != surtr.magic) {
        return error.InvalidMagic;
    }
}
