const std = @import("std");
const log = std.log.scoped(.vmx);
const Allocator = std.mem.Allocator;

const ymir = @import("ymir");
const mem = ymir.mem;
const arch = ymir.arch;
const linux = @import("linux.zig");
const impl = @import("arch/x86/vmx.zig");
const PageAllocator = ymir.mem.PageAllocator;
const BootParams = linux.BootParams;

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
        guest_image: []u8,
        initrd: []u8,
        allocator: Allocator,
        page_allocator: *PageAllocator,
    ) Error!void {
        self.guest_mem = page_allocator.allocPages(
            guest_memory_size / mem.page_size,
            mem.page_size_2mb,
        ) orelse return Error.OutOfMemory;

        try self.loadKernel(guest_image, initrd);

        const eptp = try impl.mapGuest(self.guest_mem, allocator);
        try self.vcpu.setEptp(eptp, self.guest_mem.ptr);
        log.info("Guest memory is mapped: HVA=0x{X:0>16} (size=0x{X})", .{ @intFromPtr(self.guest_mem.ptr), self.guest_mem.len });
    }

    pub fn loop(self: *Self) Error!void {
        arch.disableIntr();
        try self.vcpu.loop();
    }

    fn loadKernel(self: *Self, kernel: []u8, initrd: []u8) Error!void {
        const guest_mem = self.guest_mem;

        var bp = BootParams.from(kernel);
        bp.e820_entries = 0;

        // Setup necessary fields
        bp.hdr.type_of_loader = 0xFF;
        bp.hdr.ext_loader_ver = 0;
        bp.hdr.loadflags.loaded_high = true; // load kernel at 0x10_0000
        bp.hdr.loadflags.can_use_heap = true; // use memory 0..BOOTPARAM as heap
        bp.hdr.heap_end_ptr = linux.layout.bootparam - 0x200;
        bp.hdr.loadflags.keep_segments = true; // we set CS/DS/SS/ES to flag segments with a base of 0.
        bp.hdr.cmd_line_ptr = linux.layout.cmdline;
        bp.hdr.vid_mode = 0xFFFF; // VGA (normal)
        bp.hdr.ramdisk_image = linux.layout.initrd;
        bp.hdr.ramdisk_size = @truncate(initrd.len);

        try loadImage(guest_mem, initrd, linux.layout.initrd);

        // Setup E820 map
        bp.addE820entry(0, linux.layout.kernel_base, .ram);
        bp.addE820entry(
            linux.layout.kernel_base,
            guest_mem.len - linux.layout.kernel_base,
            .ram,
        );

        const cmdline_max_size = if (bp.hdr.cmdline_size < 256) bp.hdr.cmdline_size else 256;
        const cmdline = guest_mem[linux.layout.cmdline .. linux.layout.cmdline + cmdline_max_size];
        const cmdline_val = "console=ttyS0 earlyprintk=serial nokaslr";
        @memset(cmdline, 0);
        @memcpy(cmdline[0..cmdline_val.len], cmdline_val);

        try loadImage(guest_mem, std.mem.asBytes(&bp), linux.layout.bootparam);

        const code_offset = bp.hdr.getProtectedCodeOffset();
        const code_size = kernel.len - code_offset;
        try loadImage(
            guest_mem,
            kernel[code_offset .. code_offset + code_size],
            linux.layout.kernel_base,
        );
    }

    fn loadImage(memory: []u8, image: []u8, addr: usize) !void {
        if (memory.len < addr + image.len) {
            return Error.OutOfMemory;
        }
        @memcpy(memory[addr .. addr + image.len], image);
    }
};
