const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const surtr = b.addExecutable(.{
        .name = "BOOTX64.EFI",
        .root_source_file = b.path("surtr/boot.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .x86_64,
            .os_tag = .uefi,
        }),
        .optimize = optimize,
        .linkage = .static,
    });
    b.installArtifact(surtr);

    const out_dir_name = "img";
    const install_surtr = b.addInstallFile(
        surtr.getEmittedBin(),
        b.fmt("{s}/EFI/BOOT/{s}", .{ out_dir_name, surtr.name }),
    );
    install_surtr.step.dependOn(&surtr.step);
    b.getInstallStep().dependOn(&install_surtr.step);

    const ymir_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .ofmt = .elf,
    });
    const ymir = b.addExecutable(.{
        .name = "ymir.elf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("ymir/main.zig"),
            .target = ymir_target,
            .optimize = optimize,
            .code_model = .kernel,
        }),
        .linkage = .static,
    });
    ymir.entry = .{ .symbol_name = "kernelEntry" };
    b.installArtifact(ymir);

    const install_ymir = b.addInstallFile(
        ymir.getEmittedBin(),
        b.fmt("{s}/{s}", .{ out_dir_name, ymir.name }),
    );
    install_ymir.step.dependOn(&ymir.step);
    b.getInstallStep().dependOn(&install_ymir.step);

    const qemu_args = [_][]const u8{
        "sudo",
        "qemu-system-x86_64",
        "-m",
        "512M",
        "-bios",
        "/usr/share/ovmf/OVMF.fd",
        "-drive",
        b.fmt("file=fat:rw:{s}/{s},format=raw", .{ b.install_path, out_dir_name }),
        "-nographic",
        "-serial",
        "mon:stdio",
        "-no-reboot",
        "-enable-kvm",
        "-cpu",
        "host",
        "-s",
    };
    const qemu_cmd = b.addSystemCommand(&qemu_args);
    qemu_cmd.step.dependOn(b.getInstallStep());

    const run_qemu_step = b.step("run", "Run QEMU");
    run_qemu_step.dependOn(&qemu_cmd.step);
}
