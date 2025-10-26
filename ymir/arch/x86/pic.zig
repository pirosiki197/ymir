const bits = @import("ymir").bits;
const am = @import("asm.zig");

pub fn init() void {
    am.cli();
    defer am.sti();

    issue(Icw{ .icw1 = .{} }, primary_command_port);
    issue(Icw{ .icw1 = .{} }, secondary_command_port);

    issue(Icw{ .icw2 = .{ .offset = primary_vector_offset } }, primary_data_port);
    issue(Icw{ .icw2 = .{ .offset = secondary_vector_offset } }, secondary_data_port);

    issue(Icw{ .icw3 = .{ .cascade_id = 0b100 } }, primary_data_port);
    issue(Icw{ .icw3 = .{ .cascade_id = 2 } }, secondary_data_port);

    issue(Icw{ .icw4 = .{} }, primary_data_port);
    issue(Icw{ .icw4 = .{} }, secondary_data_port);

    setImr(0xFF, primary_data_port);
    setImr(0xFF, secondary_data_port);
}

pub const primary_vector_offset: usize = 32;
pub const secondary_vector_offset: usize = primary_vector_offset + 8;

const primary_command_port: u16 = 0x20;
const primary_data_port: u16 = primary_command_port + 1;
const secondary_command_port: u16 = 0xA0;
const secondary_data_port: u16 = secondary_command_port + 1;

pub const IrqLine = enum(u8) {
    timer = 0,
    keyboard = 1,
    secondary = 2,
    serial2 = 3,
    serial1 = 4,
    parallel23 = 5,
    floppy = 6,
    parallel1 = 7,
    rtc = 8,
    acpi = 9,
    open1 = 10,
    open2 = 11,
    mouse = 12,
    cop = 13,
    primary_ata = 14,
    secondary_ata = 15,

    pub fn isPrimary(self: IrqLine) bool {
        return @intFromEnum(self) < 8;
    }

    pub inline fn dataPort(self: IrqLine) u16 {
        return if (self.isPrimary()) primary_data_port else secondary_data_port;
    }

    pub inline fn commandPort(self: IrqLine) u16 {
        return if (self.isPrimary()) primary_command_port else secondary_command_port;
    }

    pub fn delta(self: IrqLine) u3 {
        if (self.isPrimary()) {
            return @intCast(@intFromEnum(self));
        } else {
            return @intCast(@intFromEnum(self) - 8);
        }
    }
};

pub fn setMask(irq: IrqLine) void {
    const port = irq.dataPort();
    setImr(am.inb(port) | bits.tobit(u8, irq.delta()), port);
}

pub fn unsetMask(irq: IrqLine) void {
    const port = irq.dataPort();
    setImr(am.inb(port) & ~bits.tobit(u8, irq.delta()), port);
}

pub fn notifyEoi(irq: IrqLine) void {
    issue(Ocw{ .ocw2 = .{ .eoi = true, .sl = true, .level = irq.delta() } }, irq.commandPort());
    if (!irq.isPrimary()) {
        issue(Ocw{ .ocw2 = .{ .eoi = true, .sl = true, .level = 2 } }, primary_command_port);
    }
}

const icw = enum { icw1, icw2, icw3, icw4 };
const Icw = union(icw) {
    icw1: Icw1,
    icw2: Icw2,
    icw3: Icw3,
    icw4: Icw4,

    const Icw1 = packed struct(u8) {
        icw4: bool = true,
        /// Single or cascade mode
        single: bool = false,
        /// Call address interval 4 or 8
        interval4: bool = false,
        /// Level triggered or edge triggered
        level: bool = false,
        _icw1: u1 = 1,
        _unused: u3 = 0,
    };
    const Icw2 = packed struct(u8) {
        offset: u8,
    };
    const Icw3 = packed struct(u8) {
        cascade_id: u8,
    };
    const Icw4 = packed struct(u8) {
        /// 8086/8088 mode or MCS-80/85 modde
        mode_8086: bool = true,
        /// Auto EOI or normal EOI
        auto_eoi: bool = false,
        /// Buffered mode
        buf: u2 = 0,
        full_nested: bool = false,
        _reserved: u3 = 0,
    };
};

const ocw = enum { ocw1, ocw2, ocw3 };
const Ocw = union(ocw) {
    ocw1: Ocw1,
    ocw2: Ocw2,
    ocw3: Ocw3,

    const Ocw1 = packed struct(u8) {
        /// Interrupt mask
        imr: u8,
    };
    const Ocw2 = packed struct(u8) {
        /// Target IRQ
        level: u3 = 0,
        _reserved: u2 = 0,
        eoi: bool,
        /// If set, specific EOI
        sl: bool,
        /// Rotate priority
        rotate: bool = false,
    };
    const Ocw3 = packed struct(u8) {
        /// Target register to read
        ris: Reg,
        /// Read register command
        read: bool,
        _unused1: u1 = 0,
        _reserved1: u2 = 0b01,
        _unused2: u2 = 0,
        _reserved2: u1 = 0,

        const Reg = enum(u1) { irr = 0, isr = 1 };
    };
};

fn issue(cw: anytype, port: u16) void {
    const T = @TypeOf(cw);
    if (T != Icw and T != Ocw) @compileError("Unsupported type for pic.issue()");

    switch (cw) {
        inline else => |s| am.outb(@bitCast(s), port),
    }
    am.relax();
}

fn setImr(imr: u8, port: u16) void {
    issue(Ocw{ .ocw1 = .{ .imr = imr } }, port);
}
