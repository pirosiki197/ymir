const std = @import("std");
const log = std.log.scoped(.vmx);
const Allocator = std.mem.Allocator;

const ymir = @import("ymir");
const mem = ymir.mem;
const arch = ymir.arch;
const impl = @import("arch/x86/vmx.zig");
const PageAllocator = ymir.mem.PageAllocator;

const guest_memory_size = 100 * 1024 * 1024; // 100MiB

const VmError = error{
    OutOfMemory,
    SystemNotSupported,
    UnknownError,
};

pub const Vm = struct {
    guest_mem: []u8 = undefined,
    vcpu: impl.Vcpu,

    const Self = @This();
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

    pub fn setupGuestMemory(
        self: *Self,
        allocator: Allocator,
        page_allocator: *PageAllocator,
    ) Error!void {
        self.guest_mem = page_allocator.allocPages(
            guest_memory_size / mem.page_size,
            mem.page_size_2mb,
        ) orelse return Error.OutOfMemory;

        log.info("guest_mem.len={}", .{self.guest_mem.len});

        const eptp = try impl.mapGuest(self.guest_mem, allocator);
        try self.vcpu.setEptp(eptp, self.guest_mem.ptr);
        log.info("Guest memory is mapped: HVA=0x{X:0>16} (size=0x{X})", .{ @intFromPtr(self.guest_mem.ptr), self.guest_mem.len });
    }

    pub fn loop(self: *Self) Error!void {
        arch.disableIntr();
        try self.vcpu.loop();
    }
};
