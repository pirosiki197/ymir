const std = @import("std");
const log = std.log.scoped(.vmx);
const Allocator = std.mem.Allocator;

const ymir = @import("ymir");
const arch = ymir.arch;
const impl = @import("arch/x86/vmx.zig");

const VmError = error{
    OutOfMemory,
    SystemNotSupported,
    UnknownError,
};

pub const Vm = struct {
    const Self = @This();

    vcpu: impl.Vcpu,

    pub const Error = VmError || impl.VmxError;

    pub fn new() VmError!Self {
        // 1. Check CPU vendor
        const vendor = arch.getCpuVendorId();
        if (!std.mem.eql(u8, vendor[0..], "GenuineIntel")) {
            log.err("Unsupported CPU vendor: {s}", .{vendor});
            return error.SystemNotSupported;
        }
        // 2&3. Check if VMX is supported
        if (!arch.isVmxSupported()) {
            log.err("Virtualization is not supported", .{});
            return error.SystemNotSupported;
        }

        const vcpu = impl.Vcpu.new(1);
        return .{ .vcpu = vcpu };
    }

    pub fn init(self: *Self, allocator: Allocator) Error!void {
        try self.vcpu.virtualize(allocator);
        log.info("vCPU #{X} was created.", .{self.vcpu.id});

        try self.vcpu.setupVmcs(allocator);
    }

    pub fn loop(self: *Self) Error!void {
        arch.disableIntr();
        try self.vcpu.loop();
    }
};
