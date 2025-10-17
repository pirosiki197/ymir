const std = @import("std");
const uefi = std.os.uefi;

pub const Phys = u64;
pub const Virt = u64;

pub const page_size = 4096;

pub const magic: usize = 0xDEADBEEF_CAFEBABE;

pub const BootInfo = extern struct {
    magic: usize = magic,
    memory_map: MemoryMap,
};

pub const MemoryMap = extern struct {
    descriptors: [*]uefi.tables.MemoryDescriptor,
    map_size: usize,
    map_key: usize,
    descriptor_size: usize,
    descriptor_version: u32,
};

pub const MemoryDescriptorIterator = struct {
    const Self = @This();
    const Md = uefi.tables.MemoryDescriptor;

    descriptors: [*]Md,
    current: *Md,
    descriptor_size: usize,
    total_size: usize,

    pub fn new(map: MemoryMap) Self {
        return .{
            .descriptors = map.descriptors,
            .current = @ptrCast(map.descriptors),
            .descriptor_size = map.descriptor_size,
            .total_size = map.map_size,
        };
    }

    pub fn next(self: *Self) ?*Md {
        if (@intFromPtr(self.current) >= @intFromPtr(self.descriptors) + self.total_size) {
            return null;
        }
        const md = self.current;
        self.current = @ptrFromInt(@intFromPtr(self.current) + self.descriptor_size);
        return md;
    }
};
