const elf = @import("std").elf;
const am = @import("asm.zig");
const BootServices = @import("std").os.uefi.tables.BootServices;
const surtr = @import("surtr");
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

const page_mask_4k: u64 = 0xFFF;
const num_table_entries: usize = 512;

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
    return &table[(vaddr >> shift) & 0x1FF];
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

    pub fn fromFlags(flags: u32) PageAttribute {
        if (flags & elf.PF_X != 0) {
            return .executable;
        } else if (flags & elf.PF_W != 0) {
            return .read_write;
        } else {
            return .read_only;
        }
    }
};

const PageError = error{
    NotPresent,
};

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

pub fn changeMap4k(virt: Virt, attr: PageAttribute) PageError!void {
    const rw = switch (attr) {
        .read_only, .executable => false,
        .read_write => true,
    };
    const xd = switch (attr) {
        .executable => false,
        .read_only, .read_write => true,
    };

    const lv4ent = getLv4Entry(virt, am.readCr3());
    if (!lv4ent.present) return PageError.NotPresent;
    const lv3ent = getLv3Entry(virt, lv4ent.address());
    if (!lv3ent.present) return PageError.NotPresent;
    const lv2ent = getLv2Entry(virt, lv3ent.address());
    if (!lv2ent.present) return PageError.NotPresent;
    const lv1ent = getLv1Entry(virt, lv2ent.address());
    if (!lv1ent.present) return PageError.NotPresent;

    lv1ent.rw = rw;
    lv1ent.xd = xd;
    am.flushTlbSingle(virt);
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
