const std = @import("std");
const uefi = std.os.uefi;
const elf = std.elf;
const log = std.log.scoped(.surtr);
const builtin = @import("builtin");
const defs = @import("surtr");
const blog = @import("log.zig");
const page = @import("arch/x86/page.zig");

pub const std_options = blog.default_log_option;
const BootServices = uefi.tables.BootServices;
const MemoryDescriptor = uefi.tables.MemoryDescriptor;

const page_size = defs.page_size;

pub fn main() uefi.Error!void {
    const con_out = uefi.system_table.con_out orelse return error.Aborted;
    try con_out.clearScreen();

    blog.init(con_out);

    const boot_service: *uefi.tables.BootServices = uefi.system_table.boot_services orelse {
        log.err("Failed to get boot services.", .{});
        return error.Aborted;
    };
    log.info("Got boot services.", .{});

    var fs = boot_service.locateProtocol(uefi.protocol.SimpleFileSystem, null) catch |err| {
        log.err("Failed to locate simple file system protocol: {}", .{err});
        return err;
    } orelse return;
    log.info("Located simple file system protocol.", .{});

    var root_dir = fs.openVolume() catch |err| {
        log.err("Failed to open volume: {}", .{err});
        return err;
    };
    log.info("Opened filesystem volume.", .{});

    const kernel = openFile(root_dir, "ymir.elf") catch |err| {
        log.err("Failed to open kernel file.", .{});
        return err;
    };
    log.info("Opended kernel file.", .{});

    const header_size: usize = @sizeOf(elf.Elf64_Ehdr);
    const header_buffer = boot_service.allocatePool(.loader_data, header_size) catch |err| {
        log.err("Failed to allocate memory for kernel ELF header.", .{});
        return err;
    };

    _ = kernel.read(header_buffer) catch |err| {
        log.err("Failed to read kernel ELF header.", .{});
        return err;
    };

    const elf64_header = std.mem.bytesToValue(elf.Elf64_Ehdr, header_buffer.ptr);
    const endian: std.builtin.Endian = switch (elf64_header.e_ident[elf.EI_DATA]) {
        elf.ELFDATA2LSB => .little,
        elf.ELFDATA2MSB => .big,
        else => {
            log.err("Invalid ELF data encoding: {}", .{elf64_header.e_ident[elf.EI_DATA]});
            return error.LoadError;
        },
    };

    const elf_header = elf.Header.init(elf64_header, endian);

    page.setLv4Writable(boot_service) catch |err| {
        log.err("Failed to set page table writable: {}", .{err});
        return err;
    };
    log.debug("Set page table writable.", .{});

    const Addr = elf.Elf64_Addr;
    var kernel_start_virt: Addr = std.math.maxInt(Addr);
    var kernel_start_phys: Addr align(page_size) = std.math.maxInt(Addr);
    var kernel_end_phys: Addr = 0;

    var iter = ProgramHeaderIterator.init(elf_header, kernel);
    while (true) {
        const phdr = iter.next() catch |err| {
            log.err("Failed to get program header: {}", .{err});
            return err;
        } orelse break;
        if (phdr.p_type != elf.PT_LOAD) continue;
        if (phdr.p_paddr < kernel_start_phys) kernel_start_phys = phdr.p_paddr;
        if (phdr.p_vaddr < kernel_start_virt) kernel_start_virt = phdr.p_vaddr;
        if (phdr.p_paddr + phdr.p_memsz > kernel_end_phys) kernel_end_phys = phdr.p_paddr + phdr.p_memsz;
    }

    const pages_4kib = (kernel_end_phys - kernel_start_phys + (page_size - 1)) / page_size;
    log.info("Kernel image: 0x{X:0>16} - 0x{X:0>16} (0x{X} pages)", .{ kernel_start_phys, kernel_end_phys, pages_4kib });

    _ = boot_service.allocatePages(.{ .address = @ptrFromInt(kernel_start_phys) }, .loader_data, pages_4kib) catch |err| {
        log.err("Failed to allocate memory for kernel image: {}", .{err});
        return err;
    };
    log.info("Allocated memory for kernel image @ 0x{X:0>16} ~ 0x{X:0>16}", .{ kernel_start_phys, kernel_start_phys + pages_4kib * page_size });

    for (0..pages_4kib) |i| {
        page.map4kTo(
            kernel_start_virt + page_size * i,
            kernel_start_phys + page_size * i,
            .read_write,
            boot_service,
        ) catch |err| {
            log.err("Failed to map memory for kernel image: {}", .{err});
            return err;
        };
    }

    iter = ProgramHeaderIterator.init(elf_header, kernel);
    while (true) {
        const phdr = iter.next() catch |err| {
            log.err("Failed to get program header: {}", .{err});
            return error.LoadError;
        } orelse break;
        if (phdr.p_type != elf.PT_LOAD) continue;
        kernel.setPosition(phdr.p_offset) catch |err| {
            log.err("Failed to set position for kernel image: {}", .{err});
            return err;
        };
        const segment: [*]u8 = @ptrFromInt(phdr.p_vaddr);
        _ = kernel.read(segment[0..phdr.p_memsz]) catch |err| {
            log.err("Failed to read kernel image.", .{});
            return err;
        };
        log.info("  Seg @ 0x{X:0>16} - 0x{X:0>16}", .{ phdr.p_vaddr, phdr.p_vaddr + phdr.p_memsz });

        const zero_count = phdr.p_memsz - phdr.p_filesz;
        if (zero_count > 0) {
            const ptr: [*]u8 = @ptrFromInt(phdr.p_vaddr + phdr.p_filesz);
            @memset(ptr[0..zero_count], 0);
        }
    }

    const map_buffer_size = page_size * 4;
    var map_buffer: [map_buffer_size]u8 align(@alignOf(uefi.tables.MemoryDescriptor)) = undefined;
    const memory_maps = boot_service.getMemoryMap(map_buffer[0..]) catch |err| {
        log.err("Failed to get memory map.", .{});
        return err;
    };

    var map_iter = memory_maps.iterator();
    while (map_iter.next()) |md| {
        log.debug(
            "  0x{X:0>16} - 0x{X:0>16} : {s}",
            .{ md.physical_start, md.physical_start + md.number_of_pages * page_size, @tagName(md.type) },
        );
    }

    // clean up
    boot_service.freePool(header_buffer.ptr) catch |err| {
        log.err("Failed to free memory for kernel ELF header: {}", .{err});
        return err;
    };
    kernel.close() catch |err| {
        log.err("Failed to close kernel file.", .{});
        return err;
    };
    root_dir.close() catch |err| {
        log.err("Failed to close filesystem volume.", .{});
        return err;
    };

    log.info("Exiting boot services.", .{});
    boot_service.exitBootServices(uefi.handle, memory_maps.info.key) catch {
        const map_info = boot_service.getMemoryMapInfo() catch |err| {
            log.err("Faile to get memory map info: {}", .{err});
            return err;
        };
        boot_service.exitBootServices(uefi.handle, map_info.key) catch |err| {
            log.err("Failed to exit boot services: {}", .{err});
            return err;
        };
    };

    const boot_info = defs.BootInfo{
        .magic = defs.magic,
        .memory_map = defs.MemoryMap{
            .map_size = memory_maps.info.descriptor_size * memory_maps.info.len,
            .descriptor_size = memory_maps.info.descriptor_size,
            .map_key = @intFromEnum(memory_maps.info.key),
            .descriptor_version = memory_maps.info.descriptor_version,
            .descriptors = @ptrCast(&map_buffer),
        },
    };

    const KernelEntryType = fn (defs.BootInfo) callconv(.{ .x86_64_win = .{} }) noreturn;
    const kernel_entry: *KernelEntryType = @ptrFromInt(elf_header.entry);

    kernel_entry(boot_info);
    unreachable;
}

fn openFile(root: *const uefi.protocol.File, comptime name: [:0]const u8) uefi.protocol.File.OpenError!*uefi.protocol.File {
    return try root.open(&toUcs2(name), .read, .{});
}

inline fn toUcs2(comptime s: [:0]const u8) [s.len:0]u16 {
    var ucs2: [s.len:0]u16 = [_:0]u16{0} ** (s.len);
    for (s, 0..) |c, i| {
        ucs2[i] = c;
        ucs2[i + 1] = 0;
    }
    return ucs2;
}

const ProgramHeaderIterator = struct {
    header: elf.Header,
    file: *uefi.protocol.File,
    index: usize = 0,

    const native_endian = builtin.cpu.arch.endian();

    fn init(header: elf.Header, file: *uefi.protocol.File) ProgramHeaderIterator {
        return .{
            .header = header,
            .file = file,
        };
    }

    fn next(self: *ProgramHeaderIterator) !?elf.Elf64_Phdr {
        if (self.index >= self.header.phnum) return null;
        defer self.index += 1;

        if (self.header.is_64) {
            var phdr: elf.Elf64_Phdr = undefined;
            const offset = self.header.phoff + @sizeOf(@TypeOf(phdr)) * self.index;
            try self.file.setPosition(offset);
            _ = try self.file.read(std.mem.asBytes(&phdr));

            // ELF endianness matches native endianness.
            if (self.header.endian == native_endian) return phdr;

            // Convert fields to native endianness.
            std.mem.byteSwapAllFields(elf.Elf64_Phdr, &phdr);
            return phdr;
        } else {
            return null;
        }
    }
};
