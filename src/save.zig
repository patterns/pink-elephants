const std = @import("std");
const spin = @import("spin/lib.zig");
const status = @import("web/status.zig");

comptime {
    spin.handle(saveScript);
}
pub fn main() void {
    std.debug.print("placeholder ", .{});
}

// bare minimum script to capture the received http
fn saveScript(ally: std.mem.Allocator, ret: anytype, rcv: anytype) void {
    spin.redis.debugText(ally, rcv) catch {
        std.log.err("Detail fault\x0A", .{});
        return status.internal();
    };

    ret.headers.append("Content-Type", "application/json") catch {
        std.log.err("Return header, OutOfMem\x0A", .{});
    };

    status.ok();
}
