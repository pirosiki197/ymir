const surtr = @import("surtr");

extern const __stackguard_lower: [*]const u8;

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
        return error.InvalidBootInfo;
    };
    while (true) asm volatile ("hlt");
}

fn validateBootInfo(boot_info: surtr.BootInfo) !void {
    if (boot_info.magic != surtr.magic) {
        return error.InvalidMagic;
    }
}
