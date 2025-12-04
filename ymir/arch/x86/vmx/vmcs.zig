const std = @import("std");
const vmx = @import("common.zig");

const VmxError = vmx.VmxError;

pub const PinExecCtrl = packed struct(u32) {
    const Self = @This();

    external_interrupt: bool,
    _reserved1: u2,
    nmi: bool,
    _reserved2: u1,
    virtual_nmi: bool,
    activate_vmx_preemption_timer: bool,
    process_posted_interrupts: bool,
    _reserved3: u24,

    pub fn new() Self {
        return std.mem.zeroes(Self);
    }

    pub fn load(self: Self) VmxError!void {
        const val: u32 = @bitCast(self);
        try vmx.vmwrite(ctrl.pin_exec_ctrl, val);
    }

    pub fn store() VmxError!Self {
        const val: u32 = @truncate(try vmx.vmread(ctrl.pin_exec_ctrl));
        return @bitCast(val);
    }
};

pub const PrimaryProcExecCtrl = packed struct(u32) {
    const Self = @This();

    _reserved1: u2,
    interrupt_window: bool,
    tsc_offsetting: bool,
    _reserved2: u3,
    /// HLT Exiting
    hlt: bool,
    _reserved3: u1,
    invlpg: bool,
    mwait: bool,
    rdpmc: bool,
    rdtsc: bool,
    _reserved4: u2,
    cr3load: bool,
    cr3store: bool,
    activate_teritary_controls: bool,
    _reserved: u1,
    cr8load: bool,
    cr8store: bool,
    use_tpr_shadow: bool,
    nmi_window: bool,
    mov_dr: bool,
    unconditional_io: bool,
    use_io_bitmap: bool,
    _reserved5: u1,
    monitor_trap: bool,
    use_msr_bitmap: bool,
    monitor: bool,
    pause: bool,
    activate_secondary_controls: bool,

    pub fn load(self: Self) VmxError!void {
        const val: u32 = @bitCast(self);
        try vmx.vmwrite(ctrl.proc_exec_ctrl, val);
    }

    pub fn store() VmxError!Self {
        const val: u32 = @truncate(try vmx.vmread(ctrl.proc_exec_ctrl));
        return @bitCast(val);
    }
};

pub const EntryCtrl = packed struct(u32) {
    pub const Self = @This();

    _reserved1: u2,
    load_debug_controls: bool,
    _reserved2: u6,
    ia32e_mode_guest: bool,
    entry_smm: bool,
    deactivate_dualmonitor: bool,
    _reserved3: u1,
    load_perf_global_ctrl: bool,
    load_ia32_pat: bool,
    load_ia32_efer: bool,
    load_ia32_bndcfgs: bool,
    conceal_vmx_from_pt: bool,
    load_rtit_ctl: bool,
    load_uinv: bool,
    load_cet_state: bool,
    load_guest_lbr_ctl: bool,
    load_pkrs: bool,
    _reserved4: u9,

    pub fn load(self: Self) VmxError!void {
        const val: u32 = @bitCast(self);
        try vmx.vmwrite(ctrl.entry_ctrl, val);
    }

    pub fn store() VmxError!Self {
        const val: u32 = @truncate(try vmx.vmread(ctrl.entry_ctrl));
        return @bitCast(val);
    }
};

pub const PrimaryExitCtrl = packed struct(u32) {
    const Self = @This();

    _reserved1: u2,
    save_debug: bool,
    _reserved2: u6,
    host_addr_space_size: bool,
    _reserved3: u2,
    load_perf_global_ctrl: bool,
    _reserved4: u2,
    ack_interrupt_onexit: bool,
    _reserved5: u2,
    save_ia32_pat: bool,
    load_ia32_pat: bool,
    save_ia32_efer: bool,
    load_ia32_efer: bool,
    save_vmx_preemption_timer: bool,
    clear_ia32_bndcfgs: bool,
    conceal_vmx_from_pt: bool,
    clear_ia32_rtit_ctl: bool,
    clear_ia32_lbr_ctl: bool,
    clear_uinv: bool,
    load_cet_state: bool,
    load_pkrs: bool,
    save_perf_global_ctl: bool,
    activate_secondary_controls: bool,

    pub fn load(self: Self) VmxError!void {
        const val: u32 = @bitCast(self);
        try vmx.vmwrite(ctrl.primary_exit_ctrl, val);
    }

    pub fn store() VmxError!Self {
        const val: u32 = @truncate(try vmx.vmread(ctrl.primary_exit_ctrl));
        return @bitCast(val);
    }
};

pub const ExitInfo = packed struct(u32) {
    basic_reason: ExitReason,
    _zero: u1 = 0,
    _reserved1: u10 = 0,
    _one: u1 = 1,
    pending_mtf: u1 = 0,
    exit_vmxroot: bool,
    _reserved2: u1 = 0,
    entry_failure: bool,

    pub fn load() VmxError!ExitInfo {
        return @bitCast(@as(u32, @truncate(try vmx.vmread(ro.vmexit_reason))));
    }
};

pub const ExitReason = enum(u16) {
    exception_nmi = 0,
    extintr = 1,
    triple_fault = 2,
    init = 3,
    sipi = 4,
    io_intr = 5,
    other_smi = 6,
    intr_window = 7,
    nmi_window = 8,
    task_switch = 9,
    cpuid = 10,
    getsec = 11,
    hlt = 12,
    invd = 13,
    invlpg = 14,
    rdpmc = 15,
    rdtsc = 16,
    rsm = 17,
    vmcall = 18,
    vmclear = 19,
    vmlaunch = 20,
    vmptrld = 21,
    vmptrst = 22,
    vmread = 23,
    vmresume = 24,
    vmwrite = 25,
    vmxoff = 26,
    vmxon = 27,
    cr = 28,
    dr = 29,
    io = 30,
    rdmsr = 31,
    wrmsr = 32,
    entry_fail_guest = 33,
    entry_fail_msr = 34,
    mwait = 36,
    monitor_trap = 37,
    monitor = 39,
    pause = 40,
    entry_fail_mce = 41,
    tpr_threshold = 43,
    apic = 44,
    veoi = 45,
    gdtr_idtr = 46,
    ldtr_tr = 47,
    ept = 48,
    ept_misconfig = 49,
    invept = 50,
    rdtscp = 51,
    preemption_timer = 52,
    invvpid = 53,
    wbinvd_wbnoinvd = 54,
    xsetbv = 55,
    apic_write = 56,
    rdrand = 57,
    invpcid = 58,
    vmfunc = 59,
    encls = 60,
    rdseed = 61,
    page_log_full = 62,
    xsaves = 63,
    xrstors = 64,
    pconfig = 65,
    spp = 66,
    umwait = 67,
    tpause = 68,
    loadiwkey = 69,
    enclv = 70,
    enqcmd_pasid_fail = 72,
    enqcmds_pasid_fail = 73,
    bus_lock = 74,
    timeout = 75,
    seamcall = 76,
    tdcall = 77,
};

/// Guest state area encodings.
/// cf. SDM Vol.3C 25.4, Appendix B.
pub const guest = enum(u32) {
    // Natural-width fields.
    cr0 = eg(0, .full, .natural),
    cr3 = eg(1, .full, .natural),
    cr4 = eg(2, .full, .natural),
    es_base = eg(3, .full, .natural),
    cs_base = eg(4, .full, .natural),
    ss_base = eg(5, .full, .natural),
    ds_base = eg(6, .full, .natural),
    fs_base = eg(7, .full, .natural),
    gs_base = eg(8, .full, .natural),
    ldtr_base = eg(9, .full, .natural),
    tr_base = eg(10, .full, .natural),
    gdtr_base = eg(11, .full, .natural),
    idtr_base = eg(12, .full, .natural),
    dr7 = eg(13, .full, .natural),
    rsp = eg(14, .full, .natural),
    rip = eg(15, .full, .natural),
    rflags = eg(16, .full, .natural),
    pending_debug_exceptions = eg(17, .full, .natural),
    sysenter_esp = eg(18, .full, .natural),
    sysenter_eip = eg(19, .full, .natural),
    s_cet = eg(20, .full, .natural),
    ssp = eg(21, .full, .natural),
    intr_ssp_table_addr = eg(22, .full, .natural),
    // 16-bit fields.
    es_sel = eg(0, .full, .word),
    cs_sel = eg(1, .full, .word),
    ss_sel = eg(2, .full, .word),
    ds_sel = eg(3, .full, .word),
    fs_sel = eg(4, .full, .word),
    gs_sel = eg(5, .full, .word),
    ldtr_sel = eg(6, .full, .word),
    tr_sel = eg(7, .full, .word),
    intr_status = eg(8, .full, .word),
    pml_index = eg(9, .full, .word),
    uinv = eg(10, .full, .word),
    // 32-bit fields.
    es_limit = eg(0, .full, .dword),
    cs_limit = eg(1, .full, .dword),
    ss_limit = eg(2, .full, .dword),
    ds_limit = eg(3, .full, .dword),
    fs_limit = eg(4, .full, .dword),
    gs_limit = eg(5, .full, .dword),
    ldtr_limit = eg(6, .full, .dword),
    tr_limit = eg(7, .full, .dword),
    gdtr_limit = eg(8, .full, .dword),
    idtr_limit = eg(9, .full, .dword),
    es_rights = eg(10, .full, .dword),
    cs_rights = eg(11, .full, .dword),
    ss_rights = eg(12, .full, .dword),
    ds_rights = eg(13, .full, .dword),
    fs_rights = eg(14, .full, .dword),
    gs_rights = eg(15, .full, .dword),
    ldtr_rights = eg(16, .full, .dword),
    tr_rights = eg(17, .full, .dword),
    interruptibility_state = eg(18, .full, .dword),
    activity_state = eg(19, .full, .dword),
    smbase = eg(20, .full, .dword),
    sysenter_cs = eg(21, .full, .dword),
    preemp_timer = eg(22, .full, .dword),
    // 64-bit fields.
    vmcs_link_pointer = eg(0, .full, .qword),
    dbgctl = eg(1, .full, .qword),
    pat = eg(2, .full, .qword),
    efer = eg(3, .full, .qword),
    perf_global_ctrl = eg(4, .full, .qword),
    pdpte0 = eg(5, .full, .qword),
    pdpte1 = eg(6, .full, .qword),
    pdpte2 = eg(7, .full, .qword),
    pdpte3 = eg(8, .full, .qword),
    bndcfgs = eg(9, .full, .qword),
    rtit_ctl = eg(10, .full, .qword),
    lbr_ctl = eg(11, .full, .qword),
    pkrs = eg(12, .full, .qword),
};

/// Host state area encodings.
/// cf. SDM Vol.3C 25.4, Appendix B.
pub const host = enum(u32) {
    // Natural-width fields.
    cr0 = eh(0, .full, .natural),
    cr3 = eh(1, .full, .natural),
    cr4 = eh(2, .full, .natural),
    fs_base = eh(3, .full, .natural),
    gs_base = eh(4, .full, .natural),
    tr_base = eh(5, .full, .natural),
    gdtr_base = eh(6, .full, .natural),
    idtr_base = eh(7, .full, .natural),
    sysenter_esp = eh(8, .full, .natural),
    sysenter_eip = eh(9, .full, .natural),
    rsp = eh(10, .full, .natural),
    rip = eh(11, .full, .natural),
    s_cet = eh(12, .full, .natural),
    ssp = eh(13, .full, .natural),
    intr_ssp_table_addr = eh(14, .full, .natural),
    // 16-bit fields.
    es_sel = eh(0, .full, .word),
    cs_sel = eh(1, .full, .word),
    ss_sel = eh(2, .full, .word),
    ds_sel = eh(3, .full, .word),
    fs_sel = eh(4, .full, .word),
    gs_sel = eh(5, .full, .word),
    tr_sel = eh(6, .full, .word),
    // 32-bit fields.
    sysenter_cs = eh(0, .full, .dword),
    // 64-bit fields.
    pat = eh(0, .full, .qword),
    efer = eh(1, .full, .qword),
    perf_global_ctrl = eh(2, .full, .qword),
    pkrs = eh(3, .full, .qword),
};

/// Control area encodings.
/// cf. SDM Vol.3C 25.4, Appendix B.
pub const ctrl = enum(u32) {
    // Natural-width fields.
    cr0_mask = ec(0, .full, .natural),
    cr4_mask = ec(1, .full, .natural),
    cr0_read_shadow = ec(2, .full, .natural),
    cr4_read_shadow = ec(3, .full, .natural),
    cr3_target0 = ec(4, .full, .natural),
    cr3_target1 = ec(5, .full, .natural),
    cr3_target2 = ec(6, .full, .natural),
    cr3_target3 = ec(7, .full, .natural),
    // 16-bit fields.
    vpid = ec(0, .full, .word),
    posted_intr_notif_vector = ec(1, .full, .word),
    eptp_index = ec(2, .full, .word),
    hlat_prefix_size = ec(3, .full, .word),
    pid_pointer_index = ec(4, .full, .word),
    // 32-bit fields.
    pin_exec_ctrl = ec(0, .full, .dword),
    proc_exec_ctrl = ec(1, .full, .dword),
    exception_bitmap = ec(2, .full, .dword),
    pf_ec_mask = ec(3, .full, .dword),
    pf_ec_match = ec(4, .full, .dword),
    cr3_target_count = ec(5, .full, .dword),
    primary_exit_ctrl = ec(6, .full, .dword),
    exit_msr_store_count = ec(7, .full, .dword),
    vexit_msr_load_count = ec(8, .full, .dword),
    entry_ctrl = ec(9, .full, .dword),
    entry_msr_load_count = ec(10, .full, .dword),
    entry_intr_info = ec(11, .full, .dword),
    entry_exception_ec = ec(12, .full, .dword),
    entry_inst_len = ec(13, .full, .dword),
    tpr_threshold = ec(14, .full, .dword),
    secondary_proc_exec_ctrl = ec(15, .full, .dword),
    ple_gap = ec(16, .full, .dword),
    ple_window = ec(17, .full, .dword),
    instruction_timeouts = ec(18, .full, .dword),
    // 64-bit fields.
    io_bitmap_a = ec(0, .full, .qword),
    io_bitmap_b = ec(1, .full, .qword),
    msr_bitmap = ec(2, .full, .qword),
    exit_msr_store_address = ec(3, .full, .qword),
    exit_msr_load_address = ec(4, .full, .qword),
    entry_msr_load_address = ec(5, .full, .qword),
    executive_vmcs_pointer = ec(6, .full, .qword),
    pml_address = ec(7, .full, .qword),
    tsc_offset = ec(8, .full, .qword),
    virtual_apic_address = ec(9, .full, .qword),
    apic_access_address = ec(10, .full, .qword),
    posted_intr_desc_addr = ec(11, .full, .qword),
    vm_function_controls = ec(12, .full, .qword),
    eptp = ec(13, .full, .qword),
    eoi_exit_bitmap0 = ec(14, .full, .qword),
    eoi_exit_bitmap1 = ec(15, .full, .qword),
    eoi_exit_bitmap2 = ec(16, .full, .qword),
    eoi_exit_bitmap3 = ec(17, .full, .qword),
    eptp_list_address = ec(18, .full, .qword),
    vmread_bitmap = ec(19, .full, .qword),
    vmwrite_bitmap = ec(20, .full, .qword),
    vexception_information_address = ec(21, .full, .qword),
    xss_exiting_bitmap = ec(22, .full, .qword),
    encls_exiting_bitmap = ec(23, .full, .qword),
    sub_page_permission_table_pointer = ec(24, .full, .qword),
    tsc_multiplier = ec(25, .full, .qword),
    tertiary_proc_exec_ctrl = ec(26, .full, .qword),
    enclv_exiting_bitmap = ec(27, .full, .qword),
    low_pasid_directory = ec(28, .full, .qword),
    high_pasid_directory = ec(29, .full, .qword),
    shared_eptp = ec(30, .full, .qword),
    pconfig_exiting_bitmap = ec(31, .full, .qword),
    hlatp = ec(32, .full, .qword),
    pid_pointer_table = ec(33, .full, .qword),
    secondary_exit_ctrl = ec(34, .full, .qword),
    spec_ctrl_mask = ec(37, .full, .qword),
    spec_ctrl_shadow = ec(38, .full, .qword),
};

/// Read-only area encodings.
/// cf. SDM Vol.3C 25.4, Appendix B.
pub const ro = enum(u32) {
    // Natural-width fields.
    exit_qual = er(0, .full, .natural),
    io_rcx = er(1, .full, .natural),
    io_rsi = er(2, .full, .natural),
    io_rdi = er(3, .full, .natural),
    io_rip = er(4, .full, .natural),
    guest_linear_address = er(5, .full, .natural),
    // 32-bit fields.
    vminstruction_error = er(0, .full, .dword),
    vmexit_reason = er(1, .full, .dword),
    exit_intr_info = er(2, .full, .dword),
    exit_intr_ec = er(3, .full, .dword),
    idt_vectoring_info = er(4, .full, .dword),
    idt_vectoring_ec = er(5, .full, .dword),
    exit_inst_len = er(6, .full, .dword),
    exit_inst_info = er(7, .full, .dword),
    // 64-bit fields.
    guest_physical_address = er(0, .full, .qword),
};

fn encode(
    comptime field_type: FieldType,
    comptime index: u9,
    comptime access_type: AccessType,
    comptime width: Width,
) u32 {
    return @bitCast(ComponentEncoding{
        .access_type = access_type,
        .index = index,
        .field_type = field_type,
        .width = width,
    });
}

/// Encodes a VMCS field for the guest state area.
fn eg(
    comptime index: u9,
    comptime access_type: AccessType,
    comptime width: Width,
) u32 {
    return encode(.guest_state, index, access_type, width);
}
/// Encodes a VMCS field for the host state area.
fn eh(
    comptime index: u9,
    comptime access_type: AccessType,
    comptime width: Width,
) u32 {
    return encode(.host_state, index, access_type, width);
}
/// Encodes a VMCS field for the control area.
fn ec(
    comptime index: u9,
    comptime access_type: AccessType,
    comptime width: Width,
) u32 {
    return encode(.control, index, access_type, width);
}
/// Encodes a VMCS field for the read-only area.
fn er(
    comptime index: u9,
    comptime access_type: AccessType,
    comptime width: Width,
) u32 {
    return encode(.vmexit, index, access_type, width);
}

const AccessType = enum(u1) {
    full = 0,
    high = 1,
};
const Width = enum(u2) {
    word = 0,
    qword = 1,
    dword = 2,
    natural = 3,
};
const FieldType = enum(u2) {
    control = 0,
    vmexit = 1,
    guest_state = 2,
    host_state = 3,
};
const ComponentEncoding = packed struct(u32) {
    access_type: AccessType,
    index: u9,
    field_type: FieldType,
    _reserved1: u1 = 0,
    width: Width,
    _reserved2: u17 = 0,
};
