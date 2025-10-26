const arch = @import("ymir").arch;

pub const user_intr_base = arch.intr.num_system_exceptions;

pub const pic_timer = 0 + user_intr_base;
pub const pic_keyboard = 1 + user_intr_base;
pub const pic_secondary = 2 + user_intr_base;
pub const pic_serial2 = 3 + user_intr_base;
pub const pic_serial1 = 4 + user_intr_base;
pub const pic_parallel23 = 5 + user_intr_base;
pub const pic_floppy = 6 + user_intr_base;
pub const pic_parallel1 = 7 + user_intr_base;
pub const pic_rtc = 8 + user_intr_base;
pub const pic_acpi = 9 + user_intr_base;
pub const pic_open1 = 10 + user_intr_base;
pub const pic_open2 = 11 + user_intr_base;
pub const pic_mouse = 12 + user_intr_base;
pub const pic_cop = 13 + user_intr_base;
pub const pic_primary_ata = 14 + user_intr_base;
pub const pic_secondary_ata = 15 + user_intr_base;
