const std = @import("std");
const Allocator = std.mem.Allocator;

const ymir = @import("ymir");
const mem = ymir.mem;
const am = @import("../asm.zig");
const common = @import("common.zig");

const VmxError = common.VmxError;

pub const Vcpu = struct {
    const Self = @This();

    id: usize = 0,
    vpid: u16,
    vmxon_region: *VmxonRegion = undefined,

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
};

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
