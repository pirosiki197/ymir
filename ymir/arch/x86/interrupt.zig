const log = @import("std").log;
const ymir = @import("ymir");
const idt = @import("idt.zig");
const isr = @import("isr.zig");
const am = @import("asm.zig");
pub const Context = isr.Context;

pub const num_system_exceptions = 32;

pub fn init() void {
    inline for (0..idt.max_num_gates) |i| {
        idt.setGate(i, .Interrupt64, isr.generateIsr(i));
    }
    idt.init();
    am.sti();
}

pub const Handler = *const fn (*Context) void;
pub var handlers: [256]Handler = @splat(unhandledHandler);

const max_subscribers = 10;
var subscribers: [max_subscribers]?Subscriber = @splat(null);

pub const Subscriber = struct {
    /// Context of the subscriber.
    self: *anyopaque,
    /// Context of the interrupt.
    callback: Callback,

    pub const Callback = *const fn (*anyopaque, *Context) void;
};

pub fn subscribe(ctx: *anyopaque, callback: Subscriber.Callback) !void {
    for (subscribers, 0..) |sub, i| {
        if (sub == null) {
            subscribers[i] = Subscriber{
                .callback = callback,
                .self = ctx,
            };
            return;
        }
    }
    return error.SubscriberFull;
}

pub fn dispatch(ctx: *Context) void {
    const vector = ctx.vector;
    for (subscribers) |subscriber| {
        if (subscriber) |s| s.callback(s.self, ctx);
    }
    handlers[vector](ctx);
}

pub fn registerHandler(comptime vector: u8, handler: Handler) void {
    handlers[vector] = handler;
    idt.setGate(vector, .Interrupt64, isr.generateIsr(vector));
}

fn unhandledHandler(ctx: *Context) void {
    @branchHint(.cold);

    log.err("============ Oops! ===================", .{});
    log.err("Unhandled interrupt: {s} ({})", .{
        exceptionName(ctx.vector),
        ctx.vector,
    });
    log.err("Error Code: 0x{X}", .{ctx.error_code});
    log.err("RIP    : 0x{X:0>16}", .{ctx.rip});
    log.err("EFLAGS : 0x{X:0>16}", .{ctx.rflags});
    log.err("RAX    : 0x{X:0>16}", .{ctx.registers.rax});
    log.err("RBX    : 0x{X:0>16}", .{ctx.registers.rbx});
    log.err("RCX    : 0x{X:0>16}", .{ctx.registers.rcx});
    log.err("RDX    : 0x{X:0>16}", .{ctx.registers.rdx});
    log.err("RSI    : 0x{X:0>16}", .{ctx.registers.rsi});
    log.err("RDI    : 0x{X:0>16}", .{ctx.registers.rdi});
    log.err("RSP    : 0x{X:0>16}", .{ctx.registers.rsp});
    log.err("RBP    : 0x{X:0>16}", .{ctx.registers.rbp});
    log.err("R8     : 0x{X:0>16}", .{ctx.registers.r8});
    log.err("R9     : 0x{X:0>16}", .{ctx.registers.r9});
    log.err("R10    : 0x{X:0>16}", .{ctx.registers.r10});
    log.err("R11    : 0x{X:0>16}", .{ctx.registers.r11});
    log.err("R12    : 0x{X:0>16}", .{ctx.registers.r12});
    log.err("R13    : 0x{X:0>16}", .{ctx.registers.r13});
    log.err("R14    : 0x{X:0>16}", .{ctx.registers.r14});
    log.err("R15    : 0x{X:0>16}", .{ctx.registers.r15});
    log.err("CS     : 0x{X:0>4}", .{ctx.cs});

    ymir.endlessHalt();
}

fn exceptionName(vector: u64) []const u8 {
    return switch (vector) {
        0 => "#DE: Divide Error",
        1 => "#DB: Debug",
        2 => "NMI: Non-Maskable Interrupt",
        3 => "#BP: Breakpoint",
        4 => "#OF: Overflow",
        5 => "#BR: BOUND Range Exceeded",
        6 => "#UD: Invalid Opcode",
        7 => "#NM: Device Not Available",
        8 => "#DF: Double Fault",
        10 => "#TS: Invalid TSS",
        11 => "#NP: Segment Not Present",
        12 => "#SS: Stack-Segment Fault",
        13 => "#GP: General Protection Fault",
        14 => "#PF: Page Fault",
        16 => "#MF: x87 FPU Floating-Point Error",
        17 => "#AC: Alignment Check",
        18 => "#MC: Machine Check",
        19 => "#XM: SIMD Floating-Point Exception",
        20 => "#VE: Virtualization Exception",
        21 => "#CP: Control Protection Exception",
        9, 15, 22...31 => "Reserved",
        else => "Unknown or User Defined",
    };
}
