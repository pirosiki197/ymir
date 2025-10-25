const std = @import("std");
const log = std.log.scoped(.bin_allocator);
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

page_allocator: Allocator,
list_heads: [bin_sizes.len]ChunkMetaPointer,

const Self = @This();

pub const vtable = Allocator.VTable{
    .alloc = alloc,
    .free = free,
    .resize = resize,
    .remap = remap,
};

const bin_sizes = [_]usize{
    0x20, 0x40, 0x80, 0x100, 0x200, 0x400, 0x800,
};

comptime {
    if (bin_sizes[bin_sizes.len - 1] > 4096) {
        @compileError("The largest bin size exceeds a 4KiB page size.");
    }
    if (@sizeOf(ChunkMetaNode) > bin_sizes[0]) {
        @compileError("The smallest bin size exceeds the size of ChunkMetaNode.");
    }
}

const ChunkMetaNode = struct {
    next: ChunkMetaPointer = null,
};
const ChunkMetaPointer = ?*ChunkMetaNode;

pub fn init(self: *Self, page_allocator: Allocator) void {
    self.page_allocator = page_allocator;
    @memset(self.list_heads[0..self.list_heads.len], null);
}

fn alloc(ctx: *anyopaque, n: usize, alignment: Alignment, _: usize) ?[*]u8 {
    const self: *Self = @ptrCast(@alignCast(ctx));

    if (binIndex(@max(alignment.toByteUnits(), n))) |index| {
        return self.allocFromBin(index);
    } else {
        const ret = self.page_allocator.alloc(u8, n) catch return null;
        return @ptrCast(ret.ptr);
    }
}

fn free(ctx: *anyopaque, memory: []u8, alignment: Alignment, _: usize) void {
    const self: *Self = @ptrCast(@alignCast(ctx));

    const bin_index = binIndex(@max(alignment.toByteUnits(), memory.len));
    if (bin_index) |index| {
        self.freeToBin(index, @ptrCast(memory.ptr));
    } else {
        self.page_allocator.free(memory);
    }
}

fn resize(_: *anyopaque, _: []u8, _: Alignment, _: usize, _: usize) bool {
    @panic("BinAllocator does not support resizing");
}

fn remap(_: *anyopaque, _: []u8, _: Alignment, _: usize, _: usize) ?[*]u8 {
    return null;
}

fn binIndex(size: usize) ?usize {
    for (bin_sizes, 0..) |bin_size, i| {
        if (size <= bin_size) return i;
    }
    return null;
}

fn initBinPage(self: *Self, bin_index: usize) ?void {
    const new_page = self.page_allocator.alloc(u8, 4096) catch return null;
    const bin_size = bin_sizes[bin_index];

    var i: usize = 4096 / bin_size - 1;
    while (true) : (i -= 1) {
        const chunk: *ChunkMetaNode = @ptrFromInt(@intFromPtr(new_page.ptr) + i * bin_size);
        push(&self.list_heads[bin_index], chunk);
        if (i == 0) break;
    }
}

fn allocFromBin(self: *Self, bin_index: usize) ?[*]u8 {
    log.info("Allocating from bin...", .{});
    if (self.list_heads[bin_index] == null) {
        self.initBinPage(bin_index) orelse return null;
    }
    return @ptrCast(pop(&self.list_heads[bin_index]));
}

fn push(list_head: *ChunkMetaPointer, node: *ChunkMetaNode) void {
    if (list_head.*) |next| {
        node.next = next;
        list_head.* = node;
    } else {
        list_head.* = node;
        node.next = null;
    }
}

fn pop(list_head: *ChunkMetaPointer) *ChunkMetaNode {
    if (list_head.*) |first| {
        list_head.* = first.next;
        return first;
    } else {
        @panic("BinAllocator: pop from empty list");
    }
}

fn freeToBin(self: *Self, bin_index: usize, ptr: [*]u8) void {
    const chunk: *ChunkMetaNode = @ptrCast(@alignCast(ptr));
    push(&self.list_heads[bin_index], chunk);
}
