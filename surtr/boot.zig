const std = @import("std");
const uefi = std.os.uefi;
const elf = std.elf;
const log = std.log.scoped(.surtr);
const blog = @import("log.zig");
const page = @import("arch/x86/page.zig");
pub const std_options = blog.default_log_option;

const page_size = 4096;

pub fn main() uefi.Status {
    var status: uefi.Status = undefined;

    const con_out = uefi.system_table.con_out orelse return .aborted;
    status = con_out.clearScreen();

    blog.init(con_out);

    const boot_service: *uefi.tables.BootServices = uefi.system_table.boot_services orelse {
        log.err("Failed to get boot services.", .{});
        return .aborted;
    };
    log.info("Got boot services.", .{});

    var fs: *uefi.protocol.SimpleFileSystem = undefined;
    status = boot_service.locateProtocol(&uefi.protocol.SimpleFileSystem.guid, null, @ptrCast(&fs));
    if (status != .success) {
        log.err("Failed to locate simple file system protocol.", .{});
        return status;
    }
    log.info("Located simple file system protocol.", .{});

    var root_dir: *const uefi.protocol.File = undefined;
    status = fs.openVolume(&root_dir);
    if (status != .success) {
        log.err("Failed to open volume.", .{});
        return status;
    }
    log.info("Opened filesystem volume.", .{});
    defer {
        status = root_dir.close();
        if (status != .success) {
            log.err("Failed to close filesystem volume.", .{});
        }
    }

    const kernel = openFile(root_dir, "ymir.elf") catch return .aborted;
    log.info("Opended kernel file.", .{});
    defer {
        status = kernel.close();
        if (status != .success) {
            log.err("Failed to close kernel file.", .{});
        }
    }

    var header_size: usize = @sizeOf(elf.Elf64_Ehdr);
    var header_buffer: [*]align(8) u8 = undefined;
    status = boot_service.allocatePool(.loader_data, header_size, &header_buffer);
    if (status != .success) {
        log.err("Failed to allocate memory for kernel ELF header.", .{});
        return status;
    }
    defer {
        status = boot_service.freePool(header_buffer);
        if (status != .success) {
            log.err("Failed to free memory for kernel ELF header.", .{});
        }
    }

    status = kernel.read(&header_size, header_buffer);
    if (status != .success) {
        log.err("Failed to read kernel ELF header.", .{});
        return status;
    }

    const elf_header = elf.Header.parse(header_buffer[0..@sizeOf(elf.Elf64_Ehdr)]) catch |err| {
        log.err("Failed to parse kernel ELF header: {?}", .{err});
        return .aborted;
    };
    log.info("Parsed kernel ELF header.", .{});

    page.setLv4Writable(boot_service) catch |err| {
        log.err("Failed to set page table writable: {?}", .{err});
        return .load_error;
    };
    log.debug("Set page table writable.", .{});

    const Addr = elf.Elf64_Addr;
    var kernel_start_virt: Addr = std.math.maxInt(Addr);
    var kernel_start_phys: Addr align(page_size) = std.math.maxInt(Addr);
    var kernel_end_phys: Addr = 0;

    var iter = elf_header.program_header_iterator(kernel);
    while (true) {
        const phdr = iter.next() catch |err| {
            log.err("Failed to get program header: {?}", .{err});
            return .load_error;
        } orelse break;
        if (phdr.p_type != elf.PT_LOAD) continue;
        if (phdr.p_paddr < kernel_start_phys) kernel_start_phys = phdr.p_paddr;
        if (phdr.p_vaddr < kernel_start_virt) kernel_start_virt = phdr.p_vaddr;
        if (phdr.p_paddr + phdr.p_memsz > kernel_end_phys) kernel_end_phys = phdr.p_paddr + phdr.p_memsz;
    }

    const pages_4kib = (kernel_end_phys - kernel_start_phys + (page_size - 1)) / page_size;
    log.info("Kernel image: 0x{X:0>16} - 0x{X:0>16} (0x{X} pages)", .{ kernel_start_phys, kernel_end_phys, pages_4kib });

    status = boot_service.allocatePages(.allocate_address, .loader_data, pages_4kib, @ptrCast(&kernel_start_phys));
    if (status != .success) {
        log.err("Failed to allocate memory for kernel image: {?}", .{status});
        return status;
    }
    log.info("Allocated memory for kernel image @ 0x{X:0>16} ~ 0x{X:0>16}", .{ kernel_start_phys, kernel_start_phys + pages_4kib * page_size });

    for (0..pages_4kib) |i| {
        page.map4kTo(
            kernel_start_virt + page_size * i,
            kernel_start_phys + page_size * i,
            .read_write,
            boot_service,
        ) catch |err| {
            log.err("Failed to map memory for kernel image: {?}", .{err});
            return .load_error;
        };
    }

    iter = elf_header.program_header_iterator(kernel);
    while (true) {
        const phdr = iter.next() catch |err| {
            log.err("Failed to get program header: {?}", .{err});
            return .load_error;
        } orelse break;
        if (phdr.p_type != elf.PT_LOAD) continue;
        status = kernel.setPosition(phdr.p_offset);
        if (status != .success) {
            log.err("Failed to set position for kernel image.", .{});
            return status;
        }
        const segment: [*]u8 = @ptrFromInt(phdr.p_vaddr);
        var mem_size = phdr.p_memsz;
        status = kernel.read(&mem_size, segment);
        if (status != .success) {
            log.err("Failed to read kernel image.", .{});
            return status;
        }
        log.info("  Seg @ 0x{X:0>16} - 0x{X:0>16}", .{ phdr.p_vaddr, phdr.p_vaddr + phdr.p_memsz });

        const zero_count = phdr.p_memsz - phdr.p_filesz;
        if (zero_count > 0) {
            boot_service.setMem(@ptrFromInt(phdr.p_vaddr + phdr.p_filesz), zero_count, 0);
        }
    }

    while (true) {
        asm volatile ("hlt");
    }
    return .success;
}

fn openFile(root: *const uefi.protocol.File, comptime name: [:0]const u8) !*uefi.protocol.File {
    var file: *const uefi.protocol.File = undefined;
    const status = root.open(&file, &toUcs2(name), uefi.protocol.File.efi_file_mode_read, 0);
    if (status != .success) {
        log.err("Failed to open file: {s}", .{name});
        return error.aborted;
    }
    return @constCast(file);
}

inline fn toUcs2(comptime s: [:0]const u8) [s.len:0]u16 {
    var ucs2: [s.len:0]u16 = [_:0]u16{0} ** (s.len);
    for (s, 0..) |c, i| {
        ucs2[i] = c;
        ucs2[i + 1] = 0;
    }
    return ucs2;
}
