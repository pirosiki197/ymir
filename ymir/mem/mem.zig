const surtr = @import("surtr");
const ymir = @import("ymir");
const arch = ymir.arch;
const Allocator = @import("std").mem.Allocator;

pub const Phys = surtr.Phys;
pub const Virt = surtr.Virt;

pub const PageAllocator = @import("PageAllocator.zig");
pub const BinAllocator = @import("BinAllocator.zig");

pub const page_size = 4096;
pub const page_size_2mb = 2 * 1024 * 1024;

var mapping_reconstructed = false;

pub fn reconstructMapping(allocator: Allocator) !void {
    try arch.page.reconstruct(allocator);
    mapping_reconstructed = true;
}

pub fn virt2phys(addr: anytype) Phys {
    const value = switch (@typeInfo(@TypeOf(addr))) {
        .int, .comptime_int => @as(u64, addr),
        .pointer => @as(u64, @intFromPtr(addr)),
        else => @compileError("virt2phys: invalid type"),
    };
    if (!mapping_reconstructed) {
        return value;
    } else if (value < ymir.kernel_base) {
        return value - ymir.direct_map_base;
    } else {
        return value - ymir.kernel_base;
    }
}

pub fn phys2virt(addr: u64) Virt {
    if (!mapping_reconstructed) {
        return addr;
    } else {
        return addr + ymir.direct_map_base;
    }
}

pub var page_allocator_instance: PageAllocator = undefined;
pub const page_allocator = Allocator{
    .ptr = &page_allocator_instance,
    .vtable = &PageAllocator.vtable,
};

pub fn initPageAllocator(map: surtr.MemoryMap) void {
    page_allocator_instance.init(map);
}

var bin_allocator_instance: BinAllocator = undefined;
pub const general_allocator = Allocator{
    .ptr = &bin_allocator_instance,
    .vtable = &BinAllocator.vtable,
};

pub fn initGeneralAllocator() void {
    bin_allocator_instance.init(page_allocator);
}
