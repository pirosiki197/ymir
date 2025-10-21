const std = @import("std");
const uefi = std.os.uefi;
const surtr = @import("surtr");
const MemoryMap = surtr.MemoryMap;
const MemoryDescriptorIterator = surtr.MemoryDescriptorIterator;
const Phys = surtr.Phys;
const Virt = surtr.Virt;
const ymir = @import("ymir");
const bits = ymir.bits;
const mem = @import("mem.zig");

const page_size = surtr.page_size;
const page_mask: usize = 0xFFF;

const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;
const Self = @This();
const PageAllocator = Self;

bitmap: BitMap,
frame_begin: FrameID,
frame_end: FrameID,

pub fn init(self: *Self, map: MemoryMap) void {
    self.frame_begin = 1;
    var avail_end: Phys = 0;
    var desc_iter = MemoryDescriptorIterator.new(map);

    while (desc_iter.next()) |desc| {
        if (avail_end < desc.physical_start) {
            self.markAllocated(phys2frame(avail_end), desc.number_of_pages);
        }
        const phys_end = desc.physical_start + desc.number_of_pages * page_size;
        @import("std").log.info("type: {s}, start: {d}", .{ @tagName(desc.type), desc.physical_start });
        if (isUsableMemory(desc)) {
            avail_end = phys_end;
            self.markNotUsed(phys2frame(desc.physical_start), desc.number_of_pages);
        } else {
            self.markAllocated(phys2frame(desc.physical_start), desc.number_of_pages);
        }
        self.frame_end = phys2frame(avail_end);
    }
}

pub const vtable = Allocator.VTable{
    .alloc = allocate,
    .resize = resize,
    .remap = remap,
    .free = free,
};

const gib = 1024 * 1024 * 1024;
const kib = 1024;

/// Maximum physical memory size in bytes that can be managed by this allocator.
const max_physical_size = 128 * gib;
/// Maximum page frame count.
const frame_count = max_physical_size / 4096; // 32Mi frames

/// Single unit of bitmap line.
const MapLineType = u64;
/// Bits per map line.
const bits_per_mapline = @sizeOf(MapLineType) * 8; // 64
/// Number of map lines.
const num_maplines = frame_count / bits_per_mapline; // 512Ki lines
/// Bitmap type.
const BitMap = [num_maplines]MapLineType;

const FrameID = u64;
const bytes_per_frame = 4 * kib;

const Status = enum(u1) {
    used = 0,
    unused = 1,
    pub inline fn from(boolean: bool) Status {
        return if (boolean) .used else .unused;
    }
};

fn get(self: *Self, frame: FrameID) Status {
    const line_index = frame / bits_per_mapline;
    const bit_index: u6 = @truncate(frame % bits_per_mapline);
    return Status.from(self.bitmap[line_index] & bits.tobit(MapLineType, bit_index) != 0);
}

fn set(self: *Self, frame: FrameID, status: Status) void {
    const line_index = frame / bits_per_mapline;
    const bit_index: u6 = @truncate(frame % bits_per_mapline);
    switch (status) {
        .used => self.bitmap[line_index] |= bits.tobit(MapLineType, bit_index),
        .unused => self.bitmap[line_index] &= ~bits.tobit(MapLineType, bit_index),
    }
}

fn markAllocated(self: *Self, frame: FrameID, num_frames: usize) void {
    for (0..num_frames) |i| {
        self.set(frame + i, .used);
    }
}

fn markNotUsed(self: *Self, frame: FrameID, num_frames: usize) void {
    for (0..num_frames) |i| {
        self.set(frame + i, .unused);
    }
}

inline fn phys2frame(phys: Phys) FrameID {
    return phys / bytes_per_frame;
}
inline fn frame2phys(frame: FrameID) Phys {
    return frame * bytes_per_frame;
}

inline fn isUsableMemory(descriptor: *uefi.tables.MemoryDescriptor) bool {
    return switch (descriptor.type) {
        .conventional_memory, .boot_services_code => true,
        else => false,
    };
}

fn allocate(ctx: *anyopaque, n: usize, _: Alignment, _: usize) ?[*]u8 {
    const log = @import("std").log;
    const self: *PageAllocator = @ptrCast(@alignCast(ctx));

    const num_frames = (n + page_size - 1) / page_size;
    var start_frame = self.frame_begin;

    while (true) {
        var i: usize = 0;
        while (i < num_frames) : (i += 1) {
            if (start_frame + i >= self.frame_end) {
                log.info("return null. why???", .{});
                return null;
            }
            if (self.get(start_frame + i) == .used) break;
        }
        if (i == num_frames) {
            self.markAllocated(start_frame, num_frames);
            return @ptrFromInt(mem.phys2virt(frame2phys(start_frame)));
        }

        start_frame += i + 1;
    }
}
fn resize(_: *anyopaque, _: []u8, _: Alignment, _: usize, _: usize) bool {
    @panic("PageAllocator does not support resizing.");
}
fn remap(_: *anyopaque, _: []u8, _: Alignment, _: usize, _: usize) ?[*]u8 {
    @panic("PageAllocator does not support remapping.");
}
fn free(ctx: *anyopaque, slice: []u8, _: Alignment, _: usize) void {
    const self: *PageAllocator = @ptrCast(@alignCast(ctx));

    const num_frames = (slice.len + page_size - 1) / page_size;
    const start_frame_vaddr: Virt = @intFromPtr(slice.ptr) & ~page_mask;
    const start_from = phys2frame(mem.virt2phys(start_frame_vaddr));
    self.markNotUsed(start_from, num_frames);
}

pub fn allocPages(self: *Self, num_pages: usize, align_size: usize) ?[]u8 {
    const num_frames = num_pages;
    const align_frame = (align_size + page_size - 1) / page_size;
    var start_frame = align_frame;

    while (true) {
        var i: usize = 0;
        while (i < num_frames) : (i += 1) {
            if (start_frame + i >= self.frame_end) return null;
            if (self.get(start_frame + i) == .used) break;
        }
        if (i == num_frames) {
            self.markAllocated(start_frame, num_frames);
            const virt_addr: [*]u8 = @ptrFromInt(mem.phys2virt(frame2phys(start_frame)));
            return virt_addr[0 .. num_pages * page_size];
        }

        start_frame += align_frame;
        if (start_frame + num_frames >= self.frame_end) return null;
    }
}
