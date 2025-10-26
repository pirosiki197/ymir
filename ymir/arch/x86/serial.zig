const am = @import("asm.zig");
const ymir = @import("ymir");
const Serial = ymir.serial.Serial;

pub const Port = enum(u16) {
    com1 = 0x3F8,
    com2 = 0x2F8,
    com3 = 0x3E8,
    com4 = 0x2E8,
};

const offsets = struct {
    /// Transmitter Holding Buffer: DLAB=0, W
    pub const txr = 0;
    /// Receiver Buffer: DLAB=0, R
    pub const rxr = 0;
    /// Divisor Latch Low Byte: DLAB=1, R/W
    pub const dll = 0;
    /// Interrupt Enable Register: DLAB=0, R/W
    pub const ier = 1;
    /// Divisor Latch High Byte: DLAB=1, R/W
    pub const dlh = 1;
    /// Interrupt Identification Register: DLAB=X, R
    pub const iir = 2;
    /// FIFO Control Register: DLAB=X, W
    pub const fcr = 2;
    /// Line Control Register: DLAB=X, R/W
    pub const lcr = 3;
    /// Modem Control Register: DLAB=X, R/W
    pub const mcr = 4;
    /// Line Status Register: DLAB=X, R
    pub const lsr = 5;
    /// Modem Status Register: DLAB=X, R
    pub const msr = 6;
    /// Scratch Register: DLAB=X, R/W
    pub const sr = 7;
};

pub fn initSerial(serial: *Serial, port: Port, baud: u32) void {
    const p = @intFromEnum(port);
    am.outb(0b00_000_0_00, p + offsets.lcr);
    am.outb(0, p + offsets.ier);
    am.outb(0, p + offsets.fcr);

    const divisor = 115200 / baud;
    const c = am.inb(p + offsets.lcr);
    am.outb(c | 0b1000_0000, p + offsets.lcr); // Enable DLAB
    am.outb(@truncate(divisor & 0xFF), p + offsets.dll);
    am.outb(@truncate((divisor >> 8) & 0xFF), p + offsets.dlh);
    am.outb(c & 0b0111_1111, p + offsets.lcr); // Disable DLAB

    serial._write_fn = switch (port) {
        .com1 => writeByteCom1,
        .com2 => writeByteCom1,
        .com3 => writeByteCom1,
        .com4 => writeByteCom1,
    };
}

pub fn enableInterrupt(port: Port) void {
    var ie = am.inb(@intFromEnum(port) + offsets.ier);
    ie |= @as(u8, 0b0000_0011); // Tx-empty, Rx-available
    am.outb(ie, @intFromEnum(port) + offsets.ier);
}

fn writeByteCom1(byte: u8) void {
    writeByte(byte, .com1);
}

fn writeByte(byte: u8, port: Port) void {
    while ((am.inb(@intFromEnum(port) + offsets.lsr) & 0b0010_0000) == 0) {
        am.relax();
    }

    am.outb(byte, @intFromEnum(port));
}
