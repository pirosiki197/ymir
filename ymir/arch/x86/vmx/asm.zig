const std = @import("std");
const Vcpu = @import("vcpu.zig").Vcpu;
const vmx = @import("common.zig");

export fn asmVmEntry() callconv(.naked) u8 {
    asm volatile (
        \\push %%rbp
        \\push %%r15
        \\push %%r14
        \\push %%r13
        \\push %%r12
        \\push %%rbx
    );

    asm volatile (std.fmt.comptimePrint(
            \\lea {d}(%%rdi), %%rbx
            \\push %%rbx
        ,
            .{@offsetOf(Vcpu, "guest_regs")},
        ));

    asm volatile (
        \\push %%rdi
        \\lea 8(%%rsp), %%rdi
        \\call setHostStack
        \\pop %%rdi
    );

    asm volatile (std.fmt.comptimePrint(
            \\testb $1, {d}(%%rdi)
        ,
            .{@offsetOf(Vcpu, "launch_done")},
        ));

    // Restore guest registers.
    asm volatile (std.fmt.comptimePrint(
            \\lea {[guest_regs]}(%%rdi), %%rax
            \\mov {[rcx]}(%%rax), %%rcx
            \\mov {[rdx]}(%%rax), %%rdx
            \\mov {[rbx]}(%%rax), %%rbx
            \\mov {[rsi]}(%%rax), %%rsi
            \\mov {[rdi]}(%%rax), %%rdi
            \\mov {[rbp]}(%%rax), %%rbp
            \\mov {[r8]}(%%rax), %%r8
            \\mov {[r9]}(%%rax), %%r9
            \\mov {[r10]}(%%rax), %%r10
            \\mov {[r11]}(%%rax), %%r11
            \\mov {[r12]}(%%rax), %%r12
            \\mov {[r13]}(%%rax), %%r13
            \\mov {[r14]}(%%rax), %%r14
            \\mov {[r15]}(%%rax), %%r15
            \\movaps {[xmm0]}(%%rax), %%xmm0
            \\movaps {[xmm1]}(%%rax), %%xmm1
            \\movaps {[xmm2]}(%%rax), %%xmm2
            \\movaps {[xmm3]}(%%rax), %%xmm3
            \\movaps {[xmm4]}(%%rax), %%xmm4
            \\movaps {[xmm5]}(%%rax), %%xmm5
            \\movaps {[xmm6]}(%%rax), %%xmm6
            \\movaps {[xmm7]}(%%rax), %%xmm7
            \\mov {[rax]}(%%rax), %%rax
        , .{
            .guest_regs = @offsetOf(Vcpu, "guest_regs"),
            .rax = @offsetOf(vmx.GuestRegisters, "rax"),
            .rcx = @offsetOf(vmx.GuestRegisters, "rcx"),
            .rdx = @offsetOf(vmx.GuestRegisters, "rdx"),
            .rbx = @offsetOf(vmx.GuestRegisters, "rbx"),
            .rsi = @offsetOf(vmx.GuestRegisters, "rsi"),
            .rdi = @offsetOf(vmx.GuestRegisters, "rdi"),
            .rbp = @offsetOf(vmx.GuestRegisters, "rbp"),
            .r8 = @offsetOf(vmx.GuestRegisters, "r8"),
            .r9 = @offsetOf(vmx.GuestRegisters, "r9"),
            .r10 = @offsetOf(vmx.GuestRegisters, "r10"),
            .r11 = @offsetOf(vmx.GuestRegisters, "r11"),
            .r12 = @offsetOf(vmx.GuestRegisters, "r12"),
            .r13 = @offsetOf(vmx.GuestRegisters, "r13"),
            .r14 = @offsetOf(vmx.GuestRegisters, "r14"),
            .r15 = @offsetOf(vmx.GuestRegisters, "r15"),
            .xmm0 = @offsetOf(vmx.GuestRegisters, "xmm0"),
            .xmm1 = @offsetOf(vmx.GuestRegisters, "xmm1"),
            .xmm2 = @offsetOf(vmx.GuestRegisters, "xmm2"),
            .xmm3 = @offsetOf(vmx.GuestRegisters, "xmm3"),
            .xmm4 = @offsetOf(vmx.GuestRegisters, "xmm4"),
            .xmm5 = @offsetOf(vmx.GuestRegisters, "xmm5"),
            .xmm6 = @offsetOf(vmx.GuestRegisters, "xmm6"),
            .xmm7 = @offsetOf(vmx.GuestRegisters, "xmm7"),
        }));

    asm volatile (
        \\jz .L_vmlaunch
        \\vmresume
        \\.L_vmlaunch:
        \\vmlaunch
    );

    asm volatile (
        \\mov $1, %%al
    );
    asm volatile (
        \\add $0x8, %%rsp
        \\pop %%rbx
        \\pop %%r12
        \\pop %%r13
        \\pop %%r14
        \\pop %%r15
        \\pop %%rbp
    );
    asm volatile (
        \\ret
    );
}

pub fn asmVmExit() callconv(.naked) void {
    asm volatile (
        \\cli
    );
    asm volatile (
        \\push %%rax
        \\movq 8(%%rsp), %%rax
    );

    asm volatile (std.fmt.comptimePrint(
            // Save pushed RAX.
            \\pop {[rax]}(%%rax)
            // Discard pushed &guest_regs.
            \\add $0x8, %%rsp
            // Save guest registers.
            \\mov %%rcx, {[rcx]}(%%rax)
            \\mov %%rdx, {[rdx]}(%%rax)
            \\mov %%rbx, {[rbx]}(%%rax)
            \\mov %%rsi, {[rsi]}(%%rax)
            \\mov %%rdi, {[rdi]}(%%rax)
            \\mov %%rbp, {[rbp]}(%%rax)
            \\mov %%r8, {[r8]}(%%rax)
            \\mov %%r9, {[r9]}(%%rax)
            \\mov %%r10, {[r10]}(%%rax)
            \\mov %%r11, {[r11]}(%%rax)
            \\mov %%r12, {[r12]}(%%rax)
            \\mov %%r13, {[r13]}(%%rax)
            \\mov %%r14, {[r14]}(%%rax)
            \\mov %%r15, {[r15]}(%%rax)
            \\movaps %%xmm0, {[xmm0]}(%%rax)
            \\movaps %%xmm1, {[xmm1]}(%%rax)
            \\movaps %%xmm2, {[xmm2]}(%%rax)
            \\movaps %%xmm3, {[xmm3]}(%%rax)
            \\movaps %%xmm4, {[xmm4]}(%%rax)
            \\movaps %%xmm5, {[xmm5]}(%%rax)
            \\movaps %%xmm6, {[xmm6]}(%%rax)
            \\movaps %%xmm7, {[xmm7]}(%%rax)
        ,
            .{
                .rax = @offsetOf(vmx.GuestRegisters, "rax"),
                .rcx = @offsetOf(vmx.GuestRegisters, "rcx"),
                .rdx = @offsetOf(vmx.GuestRegisters, "rdx"),
                .rbx = @offsetOf(vmx.GuestRegisters, "rbx"),
                .rsi = @offsetOf(vmx.GuestRegisters, "rsi"),
                .rdi = @offsetOf(vmx.GuestRegisters, "rdi"),
                .rbp = @offsetOf(vmx.GuestRegisters, "rbp"),
                .r8 = @offsetOf(vmx.GuestRegisters, "r8"),
                .r9 = @offsetOf(vmx.GuestRegisters, "r9"),
                .r10 = @offsetOf(vmx.GuestRegisters, "r10"),
                .r11 = @offsetOf(vmx.GuestRegisters, "r11"),
                .r12 = @offsetOf(vmx.GuestRegisters, "r12"),
                .r13 = @offsetOf(vmx.GuestRegisters, "r13"),
                .r14 = @offsetOf(vmx.GuestRegisters, "r14"),
                .r15 = @offsetOf(vmx.GuestRegisters, "r15"),
                .xmm0 = @offsetOf(vmx.GuestRegisters, "xmm0"),
                .xmm1 = @offsetOf(vmx.GuestRegisters, "xmm1"),
                .xmm2 = @offsetOf(vmx.GuestRegisters, "xmm2"),
                .xmm3 = @offsetOf(vmx.GuestRegisters, "xmm3"),
                .xmm4 = @offsetOf(vmx.GuestRegisters, "xmm4"),
                .xmm5 = @offsetOf(vmx.GuestRegisters, "xmm5"),
                .xmm6 = @offsetOf(vmx.GuestRegisters, "xmm6"),
                .xmm7 = @offsetOf(vmx.GuestRegisters, "xmm7"),
            },
        ));

    asm volatile (
        \\pop %%rbx
        \\pop %%r12
        \\pop %%r13
        \\pop %%r14
        \\pop %%r15
        \\pop %%rbp
    );

    asm volatile (
        \\mov $0, %%rax
        \\ret
    );
}
