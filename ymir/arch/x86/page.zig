const std = @import("std");
const am = @import("asm.zig");
const surtr = @import("surtr");
const ymir = @import("ymir");

const BootServices = std.os.uefi.tables.BootServices;
const Allocator = std.mem.Allocator;
const Phys = surtr.Phys;
const Virt = surtr.Virt;

const TableLevel = enum { lv4, lv3, lv2, lv1 };

fn EntryBase(table_level: TableLevel) type {
    return packed struct(u64) {
        const Self = @This();
        const level = table_level;
        const LowerType = switch (level) {
            .lv4 => Lv3Entry,
            .lv3 => Lv2Entry,
            .lv2 => Lv1Entry,
            .lv1 => struct {},
        };

        present: bool = true,
        rw: bool,
        /// whether user-mode access is allowed, or not
        us: bool,
        pwt: bool = false,
        pcd: bool = false,
        accessed: bool = false,
        dirty: bool = false,
        /// page size
        ps: bool,
        global: bool = true,
        _ignored1: u2 = 0,
        restart: bool = false,
        phys: u51,
        xd: bool = false,

        pub fn newMapPage(phys: Phys, present: bool) Self {
            if (level == .lv4) @compileError("Lv4 entry cannot map a page");
            return Self{
                .present = present,
                .rw = true,
                .us = false,
                .ps = true,
                .phys = @truncate(phys >> 12),
            };
        }

        pub fn newMapTable(table: [*]LowerType, present: bool) Self {
            if (level == .lv1) @compileError("Lv1 entry cannot reference a page table");
            return Self{
                .present = present,
                .rw = true,
                .us = false,
                .ps = false,
                .phys = @truncate(@intFromPtr(table) >> 12),
            };
        }

        pub inline fn address(self: Self) Phys {
            return @as(u64, @intCast(self.phys)) << 12;
        }
    };
}

const Lv4Entry = EntryBase(.lv4);
const Lv3Entry = EntryBase(.lv3);
const Lv2Entry = EntryBase(.lv2);
const Lv1Entry = EntryBase(.lv1);

const index_mask = 0x1FF;

const page_mask_4k: u64 = 0xFFF;
const page_shift_4k = 12;
const num_table_entries: usize = 512;

const lv4_shift = 39;
const lv3_shift = 30;

fn getTable(T: type, addr: Phys) []T {
    const ptr: [*]T = @ptrFromInt(addr & ~page_mask_4k);
    return ptr[0..num_table_entries];
}

fn getLv4Table(cr3: Phys) []Lv4Entry {
    return getTable(Lv4Entry, cr3);
}
fn getLv3Table(lv3_paddr: Phys) []Lv3Entry {
    return getTable(Lv3Entry, lv3_paddr);
}
fn getLv2Table(lv2_paddr: Phys) []Lv2Entry {
    return getTable(Lv2Entry, lv2_paddr);
}
fn getLv1Table(lv1_paddr: Phys) []Lv1Entry {
    return getTable(Lv1Entry, lv1_paddr);
}

fn getEntry(T: type, vaddr: Virt, paddr: Phys) *T {
    const table = getTable(T, paddr);
    const shift = switch (T) {
        Lv4Entry => 39,
        Lv3Entry => 30,
        Lv2Entry => 21,
        Lv1Entry => 12,
        else => @compileError("unknown type"),
    };
    return &table[(vaddr >> shift) & index_mask];
}

fn getLv4Entry(addr: Virt, cr3: Phys) *Lv4Entry {
    return getEntry(Lv4Entry, addr, cr3);
}
fn getLv3Entry(addr: Virt, lv3tbl_paddr: Phys) *Lv3Entry {
    return getEntry(Lv3Entry, addr, lv3tbl_paddr);
}
fn getLv2Entry(addr: Virt, lv2tbl_paddr: Phys) *Lv2Entry {
    return getEntry(Lv2Entry, addr, lv2tbl_paddr);
}
fn getLv1Entry(addr: Virt, lv1tbl_paddr: Phys) *Lv1Entry {
    return getEntry(Lv1Entry, addr, lv1tbl_paddr);
}

pub const PageAttribute = enum {
    read_only,
    read_write,
    executable,
};

const PageError = error{
    OutOfMemory,
};

fn allocatePage(allocator: Allocator) PageError![*]align(4096) u8 {
    return (allocator.alignedAlloc(u8, @enumFromInt(12), 4096) catch return error.OutOfMemory).ptr;
}

pub fn reconstruct(allocator: Allocator) PageError!void {
    const lv4tbl_ptr: [*]Lv4Entry = @ptrCast(try allocatePage(allocator));
    const lv4tbl = lv4tbl_ptr[0..num_table_entries];
    @memset(lv4tbl, std.mem.zeroes(Lv4Entry));

    const lv4idx_start = (ymir.direct_map_base >> lv4_shift) & index_mask;
    const lv4idx_end = lv4idx_start + (ymir.direct_map_size >> lv4_shift);

    for (lv4tbl[lv4idx_start..lv4idx_end], 0..) |*lv4ent, i| {
        const lv3tbl: [*]Lv3Entry = @ptrCast(try allocatePage(allocator));
        for (0..num_table_entries) |lv3idx| {
            lv3tbl[lv3idx] = Lv3Entry.newMapPage(
                (i << lv4_shift) + (lv3idx << lv3_shift),
                true,
            );
        }
        lv4ent.* = Lv4Entry.newMapTable(lv3tbl, true);
    }

    const old_lv4tbl = getLv4Table(am.readCr3());
    for (lv4idx_end..num_table_entries) |lv4idx| {
        if (old_lv4tbl[lv4idx].present) {
            const lv3tbl = getLv3Table(old_lv4tbl[lv4idx].address());
            const new_lv3tbl = try cloneLv3Table(lv3tbl, allocator);
            lv4tbl[lv4idx] = Lv4Entry.newMapTable(new_lv3tbl.ptr, true);
        }
    }

    const cr3 = @intFromPtr(lv4tbl.ptr) & ~@as(u64, 0xFFF);
    am.loadCr3(cr3);
}

fn allocateNewTable(T: type, entry: *T, bs: *BootServices) BootServices.AllocatePagesError!void {
    const page = try bs.allocatePages(.any, .boot_services_data, 1);
    clearPage(@intFromPtr(page.ptr));
    entry.* = T.newMapTable(@ptrCast(page.ptr), true);
}

fn clearPage(addr: Phys) void {
    const page_ptr: [*]u8 = @ptrFromInt(addr);
    @memset(page_ptr[0..4096], 0);
}

pub fn setLv4Writable(bs: *BootServices) BootServices.AllocatePagesError!void {
    const page = try bs.allocatePages(.any, .boot_services_data, 1);
    const new_lv4ptr: [*]Lv4Entry = @ptrCast(page.ptr);
    const new_lv4tbl: []Lv4Entry = new_lv4ptr[0..num_table_entries];

    const lv4tbl = getLv4Table(am.readCr3());
    @memcpy(new_lv4tbl, lv4tbl);

    am.loadCr3(@intFromPtr(new_lv4tbl.ptr));
}

fn cloneLv3Table(lv3tbl: []Lv3Entry, allocator: Allocator) PageError![]Lv3Entry {
    const new_lv3ptr: [*]Lv3Entry = @ptrCast(try allocatePage(allocator));
    const new_lv3tbl = new_lv3ptr[0..num_table_entries];
    @memcpy(new_lv3tbl, lv3tbl);

    for (new_lv3tbl) |*lv3ent| {
        if (!lv3ent.present) continue;
        if (lv3ent.ps) continue;
        const lv2tbl = getLv2Table(lv3ent.address());
        const new_lv2tbl = try cloneLv2Table(lv2tbl, allocator);
        lv3ent.phys = @truncate(ymir.mem.virt2phys(@intFromPtr(new_lv2tbl.ptr)) >> page_shift_4k);
    }

    return new_lv3tbl;
}

fn cloneLv2Table(lv2tbl: []Lv2Entry, allocator: Allocator) PageError![]Lv2Entry {
    const new_lv2ptr: [*]Lv2Entry = @ptrCast(try allocatePage(allocator));
    const new_lv2tbl = new_lv2ptr[0..num_table_entries];
    @memcpy(new_lv2tbl, lv2tbl);

    for (new_lv2tbl) |*lv2ent| {
        if (!lv2ent.present) continue;
        if (lv2ent.ps) continue;
        const lv1tbl = getLv1Table(lv2ent.address());
        const new_lv1tbl = try cloneLv1Table(lv1tbl, allocator);
        lv2ent.phys = @truncate(ymir.mem.virt2phys(@intFromPtr(new_lv1tbl.ptr)) >> page_shift_4k);
    }

    return new_lv2tbl;
}

fn cloneLv1Table(lv1tbl: []Lv1Entry, allocator: Allocator) PageError![]Lv1Entry {
    const new_lv1ptr: [*]Lv1Entry = @ptrCast(try allocatePage(allocator));
    const new_lv1tbl = new_lv1ptr[0..num_table_entries];
    @memcpy(new_lv1tbl, lv1tbl);

    return new_lv1tbl;
}

pub fn map4kTo(virt: Virt, phys: Phys, attr: PageAttribute, bs: *BootServices) BootServices.AllocatePagesError!void {
    const rw = switch (attr) {
        .read_only, .executable => false,
        .read_write => true,
    };

    const lv4ent = getLv4Entry(virt, am.readCr3());
    if (!lv4ent.present) try allocateNewTable(Lv4Entry, lv4ent, bs);

    const lv3ent = getLv3Entry(virt, lv4ent.address());
    if (!lv3ent.present) try allocateNewTable(Lv3Entry, lv3ent, bs);

    const lv2ent = getLv2Entry(virt, lv3ent.address());
    if (!lv2ent.present) try allocateNewTable(Lv2Entry, lv2ent, bs);

    const lv1ent = getLv1Entry(virt, lv2ent.address());
    if (lv1ent.present) return BootServices.AllocatePagesError.InvalidParameter;
    var new_lv1ent = Lv1Entry.newMapPage(phys, true);

    new_lv1ent.rw = rw;
    lv1ent.* = new_lv1ent;
}
