const surtr = @import("surtr");
const ymir = @import("ymir");
const arch = ymir.arch;
const Serial = ymir.serial.Serial;
const klog = ymir.klog;
const log = @import("std").log.scoped(.main);
const mem = ymir.mem;
const idefs = ymir.idefs;
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
    arch.serial.enableInterrupt(.com1);
    klog.init(serial);
    log.info("Ymir started!", .{});

    arch.gdt.init();
    log.info("Initialized GDT.", .{});

    arch.intr.init();
    log.info("Initialized IDT.", .{});

    arch.pic.init();
    arch.intr.registerHandler(idefs.pic_serial1, blobIrqHandler);
    arch.pic.unsetMask(.serial1);
    arch.intr.registerHandler(idefs.pic_timer, blobIrqHandler);
    arch.pic.unsetMask(.timer);
    log.info("Initialized PIC", .{});

    mem.initPageAllocator(boot_info.memory_map);
    log.info("Initialized page allocator.", .{});

    mem.initGeneralAllocator();
    log.info("Initialized general allocator", .{});

    log.info("Reconstructing memory mapping...", .{});
    try mem.reconstructMapping(mem.page_allocator);

    const general_allocator = mem.general_allocator;
    const p = try general_allocator.alloc(u8, 0x4);
    log.debug("p @ {*}", .{p.ptr});
    const q = try general_allocator.alloc(u8, 0x4);
    log.debug("q @ {*}", .{q.ptr});

    while (true) asm volatile ("hlt");
}

fn validateBootInfo(boot_info: surtr.BootInfo) !void {
    if (boot_info.magic != surtr.magic) {
        return error.InvalidMagic;
    }
}

fn blobIrqHandler(ctx: *arch.intr.Context) void {
    const vector: u16 = @intCast(ctx.vector - 0x20);
    arch.pic.notifyEoi(@enumFromInt(vector));
}
