const std = @import("std");
const builtin = std.builtin;
const log = std.log.scoped(.panic);
const ymir = @import("ymir");
const arch = ymir.arch;

var panicked = false;

pub fn panic_fn(msg: []const u8, _: ?*builtin.StackTrace, _: ?usize) noreturn {
    @branchHint(.cold);
    arch.disableIntr();
    log.err("{s}", .{msg});

    if (panicked) {
        log.err("Double panic detected. Halting.", .{});
        ymir.endlessHalt();
    }
    panicked = true;

    log.err("=== Stack Trace ===", .{});
    var it = std.debug.StackIterator.init(@returnAddress(), null);
    defer it.deinit();
    var i: usize = 0;
    while (it.next()) |frame| : (i += 1) {
        log.err("#{d:0>2}: 0x{X:0>16}", .{ i, frame });
    }

    ymir.endlessHalt();
}
