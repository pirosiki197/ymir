const std = @import("std");
const log = std.log.scoped(.vcpu);
const Allocator = std.mem.Allocator;

const ymir = @import("ymir");
const mem = ymir.mem;
const am = @import("../asm.zig");
const vmx = @import("common.zig");
const vmcs = @import("vmcs.zig");

const VmxError = vmx.VmxError;

export fn blobGuest() callconv(.naked) noreturn {
    while (true) asm volatile ("hlt");
}

const temp_stack_size: usize = mem.page_size;
var temp_stack: [temp_stack_size + 0x10]u8 align(0x10) = @splat(0);

fn vmexitBootstrapHandler() callconv(.naked) noreturn {
    asm volatile (
        \\call vmexitHandler
    );
}

export fn vmexitHandler() noreturn {
    log.debug("[VMEXIT handler]", .{});
    const reason = vmcs.ExitInfo.load() catch unreachable;
    log.debug("   VMEXIT reason: {}", .{reason});
    while (true) asm volatile ("hlt");
}

pub const Vcpu = struct {
    const Self = @This();

    id: usize = 0,
    vpid: u16,
    vmxon_region: *VmxonRegion = undefined,
    vmcs_region: *VmcsRegion = undefined,

    pub fn new(vpid: u16) Self {
        return .{ .vpid = vpid };
    }

    pub fn virtualize(self: *Self, allocator: Allocator) VmxError!void {
        adjustControlRegisters();

        // set VMXE bit in CR4
        var cr4 = am.readCr4();
        cr4.vmxe = true;
        am.loadCr4(@bitCast(cr4));

        self.vmxon_region = try vmxon(allocator);
    }

    pub fn setupVmcs(self: *Self, allocator: Allocator) VmxError!void {
        const vmcs_region = try VmcsRegion.new(allocator);
        vmcs_region.vmcs_revision_id = getVmcsRevisionId();
        self.vmcs_region = vmcs_region;
        try resetVmcs(self.vmcs_region);

        try setupExecCtrls(self, allocator);
        try setupExitCtrls(self);
        try setupEntryCtrls(self);
        try setupHostState(self);
        try setupGuestState(self);
    }

    pub fn loop(_: *Self) VmxError!void {
        const rflags = asm volatile (
            \\vmlaunch
            \\pushf
            \\popq %[rflags]
            : [rflags] "=r" (-> u64),
        );
        vmx.vmxtry(rflags) catch |err| {
            log.err("VMLAUNCH: {}", .{err});
            log.err("VM-instruction error number: {s}", .{@tagName(try vmx.InstructionError.load())});
        };
    }
};

const VmcsRegion = packed struct {
    vmcs_revision_id: u31,
    zero: u1 = 0,
    abort_indicator: u32,

    pub fn new(page_allocator: Allocator) VmxError!*align(mem.page_size) VmcsRegion {
        const size = am.readMsrVmxBasic().vmxon_region_size;
        const page = try page_allocator.alloc(u8, size);
        if (@intFromPtr(page.ptr) % mem.page_size != 0) {
            return error.OutOfMemory;
        }
        @memset(page, 0);
        return @ptrCast(@alignCast(page.ptr));
    }
};

fn setupExecCtrls(_: *Vcpu, _: Allocator) VmxError!void {
    const basic_msr = am.readMsrVmxBasic();

    const pin_exec_ctrl = try vmcs.PinExecCtrl.store();
    try adjustRegMandatoryBits(
        pin_exec_ctrl,
        if (basic_msr.true_control) am.readMsr(.vmx_true_pinbased_ctls) else am.readMsr(.vmx_pinbased_ctls),
    ).load();

    var ppb_exec_ctrl = try vmcs.PrimaryProcExecCtrl.store();
    ppb_exec_ctrl.hlt = false;
    ppb_exec_ctrl.activate_secondary_controls = false;
    try adjustRegMandatoryBits(
        ppb_exec_ctrl,
        if (basic_msr.true_control) am.readMsr(.vmx_true_procbased_ctls) else am.readMsr(.vmx_procbased_ctls),
    ).load();
}
fn setupExitCtrls(_: *Vcpu) VmxError!void {
    const basic_msr = am.readMsrVmxBasic();

    var exit_ctrl = try vmcs.PrimaryExitCtrl.store();
    exit_ctrl.host_addr_space_size = true;
    exit_ctrl.load_ia32_efer = true;
    try adjustRegMandatoryBits(
        exit_ctrl,
        if (basic_msr.true_control) am.readMsr(.vmx_true_exit_ctls) else am.readMsr(.vmx_exit_ctls),
    ).load();
}
fn setupEntryCtrls(_: *Vcpu) VmxError!void {
    const basic_msr = am.readMsrVmxBasic();

    var entry_ctrl = try vmcs.EntryCtrl.store();
    entry_ctrl.ia32e_mode_guest = true;
    try adjustRegMandatoryBits(
        entry_ctrl,
        if (basic_msr.true_control) am.readMsr(.vmx_true_entry_ctls) else am.readMsr(.vmx_entry_ctls),
    ).load();
}
fn setupHostState(_: *Vcpu) VmxError!void {
    const vmwrite = vmx.vmwrite;

    try vmwrite(vmcs.host.cr0, am.readCr0());
    try vmwrite(vmcs.host.cr3, am.readCr3());
    try vmwrite(vmcs.host.cr4, am.readCr4());

    try vmwrite(vmcs.host.rip, &vmexitBootstrapHandler);
    try vmwrite(vmcs.host.rsp, @intFromPtr(&temp_stack) + temp_stack_size);

    try vmwrite(vmcs.host.cs_sel, am.readSegSelector(.cs));
    try vmwrite(vmcs.host.ss_sel, am.readSegSelector(.ss));
    try vmwrite(vmcs.host.ds_sel, am.readSegSelector(.ds));
    try vmwrite(vmcs.host.es_sel, am.readSegSelector(.es));
    try vmwrite(vmcs.host.fs_sel, am.readSegSelector(.fs));
    try vmwrite(vmcs.host.gs_sel, am.readSegSelector(.gs));
    try vmwrite(vmcs.host.tr_sel, am.readSegSelector(.tr));

    try vmwrite(vmcs.host.fs_base, am.readMsr(.fs_base));
    try vmwrite(vmcs.host.gs_base, am.readMsr(.gs_base));
    try vmwrite(vmcs.host.tr_base, 0); // Not used in Ymir.
    try vmwrite(vmcs.host.gdtr_base, am.sgdt().base);
    try vmwrite(vmcs.host.idtr_base, am.sidt().base);

    try vmwrite(vmcs.host.efer, am.readMsr(.efer));
}
fn setupGuestState(_: *Vcpu) VmxError!void {
    const vmwrite = vmx.vmwrite;

    try vmwrite(vmcs.guest.cr0, am.readCr0());
    try vmwrite(vmcs.guest.cr3, am.readCr3());
    try vmwrite(vmcs.guest.cr4, am.readCr4());

    try vmwrite(vmcs.guest.cs_base, 0);
    try vmwrite(vmcs.guest.ss_base, 0);
    try vmwrite(vmcs.guest.ds_base, 0);
    try vmwrite(vmcs.guest.es_base, 0);
    try vmwrite(vmcs.guest.fs_base, 0);
    try vmwrite(vmcs.guest.gs_base, 0);
    try vmwrite(vmcs.guest.tr_base, 0);
    try vmwrite(vmcs.guest.gdtr_base, 0);
    try vmwrite(vmcs.guest.idtr_base, 0);
    try vmwrite(vmcs.guest.ldtr_base, 0xDEAD00); // Marker to indicate the guest.
    try vmwrite(vmcs.guest.cs_limit, @as(u64, std.math.maxInt(u32)));
    try vmwrite(vmcs.guest.ss_limit, @as(u64, std.math.maxInt(u32)));
    try vmwrite(vmcs.guest.ds_limit, @as(u64, std.math.maxInt(u32)));
    try vmwrite(vmcs.guest.es_limit, @as(u64, std.math.maxInt(u32)));
    try vmwrite(vmcs.guest.fs_limit, @as(u64, std.math.maxInt(u32)));
    try vmwrite(vmcs.guest.gs_limit, @as(u64, std.math.maxInt(u32)));
    try vmwrite(vmcs.guest.tr_limit, 0);
    try vmwrite(vmcs.guest.ldtr_limit, 0);
    try vmwrite(vmcs.guest.idtr_limit, 0);
    try vmwrite(vmcs.guest.gdtr_limit, 0);
    try vmwrite(vmcs.guest.cs_sel, am.readSegSelector(.cs));
    try vmwrite(vmcs.guest.ss_sel, 0);
    try vmwrite(vmcs.guest.ds_sel, 0);
    try vmwrite(vmcs.guest.es_sel, 0);
    try vmwrite(vmcs.guest.fs_sel, 0);
    try vmwrite(vmcs.guest.gs_sel, 0);
    try vmwrite(vmcs.guest.tr_sel, 0);
    try vmwrite(vmcs.guest.ldtr_sel, 0);

    const cs_right = vmx.SegmentRights{
        .rw = true,
        .dc = false,
        .executable = true,
        .desc_type = .code_data,
        .dpl = 0,
        .granularity = .kbyte,
        .long = true,
        .db = 0,
    };
    const ds_right = vmx.SegmentRights{
        .rw = true,
        .dc = false,
        .executable = false,
        .desc_type = .code_data,
        .dpl = 0,
        .granularity = .kbyte,
        .long = false,
        .db = 1,
    };
    const tr_right = vmx.SegmentRights{
        .rw = true,
        .dc = false,
        .executable = true,
        .desc_type = .system,
        .dpl = 0,
        .granularity = .byte,
        .long = false,
        .db = 0,
    };
    const ldtr_right = vmx.SegmentRights{
        .accessed = false,
        .rw = true,
        .dc = false,
        .executable = false,
        .desc_type = .system,
        .dpl = 0,
        .granularity = .byte,
        .long = false,
        .db = 0,
    };
    try vmwrite(vmcs.guest.cs_rights, cs_right);
    try vmwrite(vmcs.guest.ss_rights, ds_right);
    try vmwrite(vmcs.guest.ds_rights, ds_right);
    try vmwrite(vmcs.guest.es_rights, ds_right);
    try vmwrite(vmcs.guest.fs_rights, ds_right);
    try vmwrite(vmcs.guest.gs_rights, ds_right);
    try vmwrite(vmcs.guest.tr_rights, tr_right);
    try vmwrite(vmcs.guest.ldtr_rights, ldtr_right);

    try vmwrite(vmcs.guest.rip, &blobGuest);
    try vmwrite(vmcs.guest.efer, am.readMsr(.efer));
    try vmwrite(vmcs.guest.rflags, am.FlagsRegister.new());

    try vmwrite(vmcs.guest.vmcs_link_pointer, std.math.maxInt(u64));
}

fn resetVmcs(vmcs_region: *VmcsRegion) VmxError!void {
    try am.vmclear(mem.virt2phys(vmcs_region));
    try am.vmptrld(mem.virt2phys(vmcs_region));
}

fn adjustControlRegisters() void {
    const vmx_cr0_fixed0: u32 = @truncate(am.readMsr(.vmx_cr0_fixed0));
    const vmx_cr0_fixed1: u32 = @truncate(am.readMsr(.vmx_cr0_fixed1));
    const vmx_cr4_fixed0: u32 = @truncate(am.readMsr(.vmx_cr4_fixed0));
    const vmx_cr4_fixed1: u32 = @truncate(am.readMsr(.vmx_cr4_fixed1));

    var cr0: u64 = @bitCast(am.readCr0());
    cr0 |= vmx_cr0_fixed0;
    cr0 &= vmx_cr0_fixed1;
    var cr4: u64 = @bitCast(am.readCr4());
    cr4 |= vmx_cr4_fixed0;
    cr4 &= vmx_cr4_fixed1;

    am.loadCr0(cr0);
    am.loadCr4(cr4);
}

fn adjustRegMandatoryBits(control: anytype, mask: u64) @TypeOf(control) {
    var ret: u32 = @bitCast(control);
    ret |= @as(u32, @truncate(mask));
    ret &= @as(u32, @truncate(mask >> 32));
    return @bitCast(ret);
}

inline fn getVmcsRevisionId() u31 {
    return am.readMsrVmxBasic().vmcs_revision_id;
}

fn vmxon(allocator: Allocator) VmxError!*VmxonRegion {
    const vmxon_region = try VmxonRegion.new(allocator);
    vmxon_region.vmcs_revision_id = getVmcsRevisionId();
    const vmxon_phys = mem.virt2phys(vmxon_region);

    try am.vmxon(vmxon_phys);

    return vmxon_region;
}

const VmxonRegion = packed struct {
    vmcs_revision_id: u31,
    zero: u1 = 0,

    pub fn new(page_allocator: Allocator) VmxError!*align(mem.page_size) VmxonRegion {
        const size = am.readMsrVmxBasic().vmxon_region_size;
        const page = page_allocator.alloc(u8, size) catch return error.OutOfMemory;
        if (@intFromPtr(page.ptr) % mem.page_size != 0) {
            return error.OutOfMemory;
        }
        @memset(page, 0);
        return @ptrCast(@alignCast(page.ptr));
    }
};
