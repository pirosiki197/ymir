const std = @import("std");
const log = std.log.scoped(.vmc);

const Vcpu = @import("vcpu.zig").Vcpu;
const VmxError = @import("common.zig").VmxError;

const VmcallNr = enum(u64) {
    hello = 0,
    _,
};

pub fn handleVmcall(vcpu: *Vcpu) VmxError!void {
    const rax = vcpu.guest_regs.rax;
    const nr: VmcallNr = @enumFromInt(rax);

    switch (nr) {
        .hello => try vmcHello(vcpu),
        _ => log.err("Unhandled VMCALL: nr={d}", .{rax}),
    }
}

const logo =
    \\   ____     __ ,---.    ,---..-./`) .-------.
    \\   \   \   /  /|    \  /    |\ .-.')|  _ _   \
    \\    \  _. /  ' |  ,  \/  ,  |/ `-' \| ( ' )  |
    \\     _( )_ .'  |  |\_   /|  | `-'`"`|(_ o _) /
    \\ ___(_ o _)'   |  _( )_/ |  | .---. | (_,_).' __
    \\|   |(_,_)'    | (_ o _) |  | |   | |  |\ \  |  |
    \\|   `-'  /     |  (_,_)  |  | |   | |  | \ `'   /
    \\ \      /      |  |      |  | |   | |  |  \    /
    \\  `-..-'       '--'      '--' '---' ''-'   `'-'
;

fn vmcHello(_: *Vcpu) VmxError!void {
    log.info("GREETINGS FROM VMX-ROOT...\n{s}\n", .{logo});
    log.info("This OS is hypervisored by Ymir.\n", .{});
}
