const surtr = @import("surtr");
const Allocator = @import("std").mem.Allocator;
const Phys = surtr.Phys;
const Virt = surtr.Virt;

pub fn virt2phys(addr: anytype) Phys {
    return @intCast(addr);
}
pub fn phys2virt(addr: anytype) Virt {
    return @intCast(addr);
}

pub const PageAllocator = @import("PageAllocator.zig");
pub var page_allocator_instance = PageAllocator.newUninitialized();
pub const page_allocator = Allocator{
    .ptr = &page_allocator_instance,
    .vtable = &PageAllocator.vtable,
};

pub fn initPageAllocator(map: surtr.MemoryMap) void {
    page_allocator_instance.init(map);
}
