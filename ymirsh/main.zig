fn asmVmcall(nr: u64) void {
    asm volatile (
        \\movq %[nr], %%rax
        \\vmcall
        :
        : [nr] "rax" (nr),
        : .{ .memory = true }
    );
}

pub fn main() !void {
    asmVmcall(0);
}
