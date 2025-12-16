const std = @import("std");
const log = std.log.scoped(.ept);
const Allocator = std.mem.Allocator;

const surtr = @import("surtr");
const mem = @import("ymir").mem;
const Phys = surtr.Phys;
const page_shift_4k = surtr.page_shift_4k;
const page_mask_4k = surtr.page_mask;
const page_size_2mb = mem.page_size_2mb;

const virt2phys = mem.virt2phys;
const phys2virt = mem.phys2virt;

const Error = @import("common.zig").VmxError;

pub const Eptp = packed struct(u64) {
    /// Memory type.
    type: MemoryType = .write_back,
    /// EPT page-walk length.
    level: PageLevel = .four,
    /// Enable dirty and accessed flags for EPT.
    enable_ad: bool = true,
    /// Enable enforcement of access rights for supervisor shadow-stack pages.
    enable_ar: bool = false,
    /// Reserved.
    _reserved1: u4 = 0,
    /// 4KB aligned address of the Level-4 EPT table.
    phys: u52,

    pub fn new(lv4tbl: []Lv4Entry) Eptp {
        return Eptp{
            .phys = @truncate(virt2phys(lv4tbl.ptr) >> page_shift_4k),
        };
    }

    /// Get the host virtual address of the Level-4 EPT table.
    pub fn getLv4(self: *Eptp) []Lv4Entry {
        const virt: [*]Lv4Entry = @ptrFromInt(phys2virt(@as(u64, @intCast(self.phys)) << page_shift_4k));
        return virt[0..num_table_entries];
    }

    const PageLevel = enum(u3) {
        four = 3,
        five = 4,
    };
};

pub fn initEpt(
    guest_start: Phys,
    host_start: Phys,
    size: usize,
    allocator: Allocator,
) Error!Eptp {
    const lv4tbl = try initTable(Lv4Entry, allocator);
    log.debug("EPT Level4 Table @ {X:0>16}", .{@intFromPtr(lv4tbl.ptr)});

    for (0..size / page_size_2mb) |i| {
        try map2m(
            guest_start + page_size_2mb * i,
            host_start + page_size_2mb * i,
            lv4tbl,
            allocator,
        );
    }

    return Eptp.new(lv4tbl);
}

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

        /// Whether reads are allowed.
        read: bool = true,
        /// Whether writes are allowed.
        write: bool = true,
        /// If "mode-based execute control for EPT" is 0, execute access.
        /// If that field is 1, execute access for supervisor-mode linear address.
        exec_super: bool = true,
        /// EPT memory type.
        /// ReservedZ when the entry maps a page.
        type: MemoryType = .uncacheable,
        /// Ignore PAT memory type.
        ignore_pat: bool = false,
        /// If true, this entry maps memory. Otherwise, this references a page table.
        map_memory: bool,
        /// If EPTP[6] is 1, accessed flag. Otherwise, ignored.
        accessed: bool = false,
        // If EPTP[6] is 1, dirty flag. Otherwise, ignored.
        dirty: bool = false,
        /// Execute access for user-mode linear address.
        exec_user: bool = true,
        /// Ignored
        _ignored2: u1 = 0,
        /// 4KB aligned physical address of the mapped page or page table.
        phys: u52,

        /// Return true if the entry is present
        pub fn present(self: Self) bool {
            return self.read or self.write or self.exec_super;
        }

        /// Get the physical address of the page or page table that this entry references or maps
        pub inline fn address(self: Self) Phys {
            return @as(u64, @intCast(self.phys)) << page_shift_4k;
        }

        /// Get a new page table entry that references a page table
        pub fn newMapTable(table: []LowerType) Self {
            if (level == .lv1) @compileError("Lv1 EPT entry cannot reference a page table");
            return Self{
                .map_memory = false,
                .type = .uncacheable,
                .phys = @truncate(virt2phys(table.ptr) >> page_shift_4k),
            };
        }

        /// Get a new page table entry that maps a page
        pub fn newMapPage(phys: Phys) Self {
            if (level == .lv4) @compileError("Lv4 EPT entry cannot map a page");
            return Self{
                .read = true,
                .write = true,
                .exec_super = true,
                .exec_user = true,
                .map_memory = true,
                .type = @enumFromInt(0),
                .phys = @truncate(virt2phys(phys) >> page_shift_4k),
            };
        }
    };
}

const Lv4Entry = EntryBase(.lv4);
const Lv3Entry = EntryBase(.lv3);
const Lv2Entry = EntryBase(.lv2);
const Lv1Entry = EntryBase(.lv1);

const TableLevel = enum {
    lv4,
    lv3,
    lv2,
    lv1,
};

const MemoryType = enum(u3) {
    uncacheable = 0,
    write_back = 6,
};

const index_mask = 0x1FF;

const num_table_entries: usize = 512;

const lv4_shift = 39;
const lv3_shift = 30;
const lv2_shift = 21;
const lv1_shift = 12;

fn initTable(T: type, allocator: Allocator) Error![]T {
    const tbl = try allocator.alloc(T, num_table_entries);
    for (0..tbl.len) |i| {
        tbl[i].read = false;
        tbl[i].write = false;
        tbl[i].exec_super = false;
        tbl[i].map_memory = false;
        tbl[i].type = @enumFromInt(0);
    }
    return tbl;
}

fn getTable(T: type, addr: Phys) []T {
    const ptr: [*]T = @ptrFromInt(phys2virt(addr));
    return ptr[0..num_table_entries];
}

fn getEntry(T: type, gpa: Phys, tbl_paddr: Phys) *T {
    const table = getTable(T, tbl_paddr);
    const shift = switch (T) {
        Lv4Entry => lv4_shift,
        Lv3Entry => lv3_shift,
        Lv2Entry => lv2_shift,
        Lv1Entry => lv1_shift,
        else => @compileError("Invalid type"),
    };
    return &table[(gpa >> shift) & index_mask];
}

fn getLv4Entry(gpa: Phys, lv3_paddr: Phys) *Lv4Entry {
    return getEntry(Lv4Entry, gpa, lv3_paddr);
}
fn getLv3Entry(gpa: Phys, lv3tbl_paddr: Phys) *Lv3Entry {
    return getEntry(Lv3Entry, gpa, lv3tbl_paddr);
}
fn getLv2Entry(gpa: Phys, lv2tbl_paddr: Phys) *Lv2Entry {
    return getEntry(Lv2Entry, gpa, lv2tbl_paddr);
}
fn getLv1Entry(gpa: Phys, lv1tbl_paddr: Phys) *Lv1Entry {
    return getEntry(Lv1Entry, gpa, lv1tbl_paddr);
}

fn map2m(guest_phys: Phys, host_phys: Phys, lv4tbl: []Lv4Entry, allocator: Allocator) Error!void {
    const lv4index = (guest_phys >> lv4_shift) & index_mask;
    const lv4ent = &lv4tbl[lv4index];
    if (!lv4ent.present()) {
        const lv3tbl = try initTable(Lv3Entry, allocator);
        lv4ent.* = Lv4Entry.newMapTable(lv3tbl);
    }

    const lv3ent = getLv3Entry(guest_phys, lv4ent.address());
    if (!lv3ent.present()) {
        const lv2tbl = try initTable(Lv2Entry, allocator);
        lv3ent.* = Lv3Entry.newMapTable(lv2tbl);
    }
    if (lv3ent.map_memory) return error.AlreadyMapped;

    const lv2ent = getLv2Entry(guest_phys, lv3ent.address());
    if (lv2ent.present()) return error.AlreadyMapped;
    lv2ent.* = Lv2Entry{
        .map_memory = true,
        .phys = @truncate(host_phys >> page_shift_4k),
    };
}
