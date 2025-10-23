pub inline fn inb(port: u16) u8 {
    return asm volatile (
        \\inb %[port], %[ret]
        : [ret] "={al}" (-> u8),
        : [port] "{dx}" (port),
    );
}
pub inline fn outb(value: u8, port: u16) void {
    asm volatile (
        \\outb %[value], %[port]
        :
        : [value] "{al}" (value),
          [port] "{dx}" (port),
    );
}

pub inline fn relax() void {
    asm volatile (
        \\rep
        \\nop
    );
}

pub inline fn lgdt(gdtr: u64) void {
    asm volatile (
        \\ lgdt (%[gdtr])
        :
        : [gdtr] "r" (gdtr),
    );
}

pub inline fn lidt(idtr: u64) void {
    asm volatile (
        \\ lidt (%[idtr])
        :
        : [idtr] "r" (idtr),
    );
}

pub inline fn cli() void {
    asm volatile ("cli");
}

pub inline fn sti() void {
    asm volatile ("sti");
}

pub inline fn readCr3() u64 {
    var cr3: u64 = undefined;
    asm volatile (
        \\ mov %%cr3, %[cr3]
        : [cr3] "=r" (cr3),
    );
    return cr3;
}

pub inline fn loadCr3(cr3: u64) void {
    asm volatile (
        \\ mov %[cr3], %%cr3
        :
        : [cr3] "r" (cr3),
    );
}
