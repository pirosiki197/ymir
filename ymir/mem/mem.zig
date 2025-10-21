const surtr = @import("surtr");
const ymir = @import("ymir");
const arch = ymir.arch;
const Allocator = @import("std").mem.Allocator;
const Phys = surtr.Phys;
const Virt = surtr.Virt;

var mapping_reconstructed = false;

pub fn reconstructMapping(allocator: Allocator) !void {
    try arch.page.reconstruct(allocator);
    mapping_reconstructed = true;
}

pub fn virt2phys(addr: u64) Phys {
    if (!mapping_reconstructed) {
        return addr;
    } else if (addr < ymir.kernel_base) {
        return addr - ymir.direct_map_base;
    } else {
        return addr - ymir.kernel_base;
    }
}

pub fn phys2virt(addr: u64) Virt {
    if (!mapping_reconstructed) {
        return addr;
    } else {
        return addr + ymir.direct_map_base;
    }
}

pub const PageAllocator = @import("PageAllocator.zig");
pub var page_allocator_instance: PageAllocator = undefined;
pub const page_allocator = Allocator{
    .ptr = &page_allocator_instance,
    .vtable = &PageAllocator.vtable,
};

pub fn initPageAllocator(map: surtr.MemoryMap) void {
    page_allocator_instance.init(map);
}
