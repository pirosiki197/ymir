const std = @import("std");
const uefi = std.os.uefi;
const elf = std.elf;
const log = std.log.scoped(.surtr);
const blog = @import("log.zig");
const page = @import("arch/x86/page.zig");
pub const std_options = blog.default_log_option;

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

    const kernel = openFile(root_dir, "ymir.elf") catch return .aborted;
    log.info("Opended kernel file.", .{});

    var header_size: usize = @sizeOf(elf.Elf64_Ehdr);
    var header_buffre: [*]align(8) u8 = undefined;
    status = boot_service.allocatePool(.loader_data, header_size, &header_buffre);
    if (status != .success) {
        log.err("Failed to allocate memory for kernel ELF header.", .{});
        return status;
    }

    status = kernel.read(&header_size, header_buffre);
    if (status != .success) {
        log.err("Failed to read kernel ELF header.", .{});
        return status;
    }
    log.info("elf header size: {d}", .{header_size});

    const elf_header = elf.Header.parse(header_buffre[0..@sizeOf(elf.Elf64_Ehdr)]) catch |err| {
        log.err("Failed to parse kernel ELF header: {?}", .{err});
        return .aborted;
    };
    log.info("Parsed kernel ELF header.", .{});

    log.debug("Kernel information: Entry Point: 0x{X}", .{elf_header.entry});

    page.setLv4Writable(boot_service) catch |err| {
        log.err("Failed to set page table writable: {?}", .{err});
        return .load_error;
    };
    log.debug("Set page table writable.", .{});

    page.map4kTo(0xFFFF_FFFF_DEAD_0000, 0x10_0000, .read_write, boot_service) catch |err| {
        log.err("Failed to map 4KiB page: {?}", .{err});
        return .aborted;
    };

    while (true) {
        asm volatile ("hlt");
    }
    return .success;
}

fn openFile(root: *const uefi.protocol.File, comptime name: [:0]const u8) !*const uefi.protocol.File {
    var file: *const uefi.protocol.File = undefined;
    const status = root.open(&file, &toUcs2(name), uefi.protocol.File.efi_file_mode_read, 0);
    if (status != .success) {
        log.err("Failed to open file: {s}", .{name});
        return error.aborted;
    }
    return file;
}

inline fn toUcs2(comptime s: [:0]const u8) [s.len:0]u16 {
    var ucs2: [s.len:0]u16 = [_:0]u16{0} ** (s.len);
    for (s, 0..) |c, i| {
        ucs2[i] = c;
        ucs2[i + 1] = 0;
    }
    return ucs2;
}
