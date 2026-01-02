const std = @import("std");
const log = std.log.scoped(.io);

const arch = @import("../arch.zig");
const am = @import("../asm.zig");
const vmx = @import("common.zig");
const Vcpu = @import("vcpu.zig").Vcpu;
const QualIo = vmx.qual.QualIo;
const VmxError = vmx.VmxError;

pub fn handleIo(vcpu: *Vcpu, qual: QualIo) VmxError!void {
    return switch (qual.direction) {
        .in => try handleIoIn(vcpu, qual),
        .out => try handleIoOut(vcpu, qual),
    };
}

fn handleIoIn(vcpu: *Vcpu, qual: QualIo) VmxError!void {
    const regs = &vcpu.guest_regs;
    switch (qual.port) {
        0x0CF8...0x0CFF => regs.rax = 0, // PCI. Unimplemented.
        0xC000...0xCFFF => {}, // Old PCI. Ignore.
        0x02E8...0x02EF => {}, // Fourth serial port. Ignore.
        0x02F8...0x02FF => {}, // Second serial port. Ignore.
        0x03E8...0x03EF => {}, // Third serial port. Ignore.
        0x03F8...0x03FF => try handleSerialIn(vcpu, qual),
        0x0040...0x0047 => try handlePitIn(vcpu, qual),
        0x20, 0x21, 0xA0, 0xA1 => try handlePicIn(vcpu, qual),
        0x0060...0x0064 => regs.rax = 0,
        0x0070...0x0071 => regs.rax = 0,
        0x0080...0x008F => {},
        0x03B0...0x03DF => regs.rax = 0,
        else => {
            log.err("Unhandled I/O-in port: 0x{X}", .{qual.port});
            vcpu.abort();
        },
    }
}

fn handleIoOut(vcpu: *Vcpu, qual: QualIo) VmxError!void {
    switch (qual.port) {
        0x0CF8...0x0CFF => {}, // PCI. Unimplemented.
        0xC000...0xCFFF => {}, // Old PCI. Ignore.
        0x02E8...0x02EF => {}, // Fourth serial port. Ignore.
        0x02F8...0x02FF => {}, // Second serial port. Ignore.
        0x03E8...0x03EF => {}, // Third serial port. Ignore.
        0x03F8...0x03FF => try handleSerialOut(vcpu, qual),
        0x0040...0x0047 => try handlePitOut(vcpu, qual),
        0x20, 0x21, 0xA0, 0xA1 => try handlePicOut(vcpu, qual),
        0x0060...0x0064 => {},
        0x0070...0x0071 => {},
        0x0080...0x008F => {},
        0x03B0...0x03DF => {},
        else => {
            log.err("Unhandled I/O-out port: 0x{X}", .{qual.port});
            vcpu.abort();
        },
    }
}

pub const Serial = struct {
    /// Interrupt Enable Register
    ier: u8 = 0,
    /// Modem Control Register
    mcr: u8 = 0,

    pub const init = Serial{};
};

fn handleSerialIn(vcpu: *Vcpu, qual: QualIo) VmxError!void {
    const regs = &vcpu.guest_regs;
    switch (qual.port) {
        // Receive buffer.
        0x3F8 => regs.rax = am.inb(qual.port), // pass-through
        // Interrupt Enable Register (DLAB=1) / Divisor Latch High Register (DLAB=0).
        0x3F9 => regs.rax = vcpu.serial.ier,
        // Interrupt Identification Register.
        0x3FA => regs.rax = am.inb(qual.port), // pass-through
        // Line Control Register (MSB is DLAB).
        0x3FB => regs.rax = 0x00,
        // Modem Control Register.
        0x3FC => regs.rax = vcpu.serial.mcr,
        // Line Status Register.
        0x3FD => regs.rax = am.inb(qual.port), // pass-through
        // Modem Status Register.
        0x3FE => regs.rax = am.inb(qual.port), // pass-through
        // Scratch Register.
        0x3FF => regs.rax = 0, // 8250
        else => {
            log.err("Unsupported I/O-in to the first serial port: 0x{X}", .{qual.port});
            vcpu.abort();
        },
    }
}

const sr = arch.serial;

fn handleSerialOut(vcpu: *Vcpu, qual: QualIo) VmxError!void {
    const regs = &vcpu.guest_regs;
    switch (qual.port) {
        // Transmit buffer.
        0x3F8 => sr.writeByte(@truncate(regs.rax), .com1),
        // Interrupt Enable Register.
        0x3F9 => vcpu.serial.ier = @truncate(regs.rax),
        // FIFO control registers.
        0x3FA => {}, // ignore
        // Line Control Register (MSB is DLAB).
        0x3FB => {}, // ignore
        // Modem Control Register.
        0x3FC => vcpu.serial.mcr = @truncate(regs.rax),
        // Scratch Register.
        0x3FF => {}, // ignore
        else => {
            log.err("Unsupported I/O-out to the first serial port: 0x{X}", .{qual.port});
            vcpu.abort();
        },
    }
}

fn handlePitIn(vcpu: *Vcpu, qual: QualIo) VmxError!void {
    const regs = &vcpu.guest_regs;
    switch (qual.size) {
        .byte => regs.rax = @as(u64, am.inb(qual.port)),
        .word => regs.rax = @as(u64, am.inw(qual.port)),
        .dword => regs.rax = @as(u64, am.inl(qual.port)),
    }
}

fn handlePitOut(vcpu: *Vcpu, qual: QualIo) VmxError!void {
    switch (qual.size) {
        .byte => am.outb(@truncate(vcpu.guest_regs.rax), qual.port),
        .word => am.outw(@truncate(vcpu.guest_regs.rax), qual.port),
        .dword => am.outl(@truncate(vcpu.guest_regs.rax), qual.port),
    }
}

pub const Pic = struct {
    /// Mask of the primary PIC.
    primary_mask: u8,
    /// Mask of the secondary PIC.
    secondary_mask: u8,
    /// Initialization phase of the primary PIC.
    primary_phase: InitPhase = .uninitialized,
    /// Initialization phase of the secondary PIC.
    secondary_phase: InitPhase = .uninitialized,
    /// Vector offset of the primary PIC.
    primary_base: u8 = 0,
    /// Vector offset of the secondary PIC.
    secondary_base: u8 = 0,

    const InitPhase = enum {
        uninitialized, // Before ICW1
        phase1, // After ICW1
        phase2, // After ICW2
        phase3, // After ICW3
        initialized, // After ICW4, initialized.
    };

    pub const init = Pic{
        .primary_mask = 0xFF,
        .secondary_mask = 0xFF,
    };
};

fn handlePicIn(vcpu: *Vcpu, qual: QualIo) VmxError!void {
    const regs = &vcpu.guest_regs;
    const pic = &vcpu.pic;

    switch (qual.port) {
        // Primary PIC data.
        0x21 => switch (pic.primary_phase) {
            .uninitialized, .initialized => regs.rax = pic.primary_mask,
            else => vcpu.abort(),
        },
        // Secondary PIC data.
        0xA1 => switch (pic.secondary_phase) {
            .uninitialized, .initialized => regs.rax = pic.secondary_mask,
            else => vcpu.abort(),
        },
        else => vcpu.abort(),
    }
}

fn handlePicOut(vcpu: *Vcpu, qual: QualIo) VmxError!void {
    const regs = &vcpu.guest_regs;
    const pic = &vcpu.pic;
    const dx: u8 = @truncate(regs.rax);

    switch (qual.port) {
        // Primary PIC command.
        0x20 => switch (dx) {
            0x11 => pic.primary_phase = .phase1,
            // Specific-EOI.
            // It's Ymir's responsibility to send EOI, so guests are not allowed to send EOI.
            0x60...0x67 => {},
            else => vcpu.abort(),
        },
        // Primary PIC data.
        0x21 => switch (pic.primary_phase) {
            .uninitialized, .initialized => pic.primary_mask = dx,
            .phase1 => {
                log.info("Primary PIC vector offset: 0x{X}", .{dx});
                pic.primary_base = dx;
                pic.primary_phase = .phase2;
            },
            .phase2 => if (dx != (1 << 2)) {
                vcpu.abort();
            } else {
                pic.primary_phase = .phase3;
            },
            .phase3 => pic.primary_phase = .initialized,
        },

        // Secondary PIC command.
        0xA0 => switch (dx) {
            0x11 => pic.secondary_phase = .phase1,
            // Specific-EOI.
            // It's Ymir's responsibility to send EOI, so guests are not allowed to send EOI.
            0x60...0x67 => {},
            else => vcpu.abort(),
        },
        // Secondary PIC data.
        0xA1 => switch (pic.secondary_phase) {
            .uninitialized, .initialized => pic.secondary_mask = dx,
            .phase1 => {
                log.info("Secondary PIC vector offset: 0x{X}", .{dx});
                pic.secondary_base = dx;
                pic.secondary_phase = .phase2;
            },
            .phase2 => if (dx != 2) {
                vcpu.abort();
            } else {
                pic.secondary_phase = .phase3;
            },
            .phase3 => pic.secondary_phase = .initialized,
        },
        else => vcpu.abort(),
    }
}
