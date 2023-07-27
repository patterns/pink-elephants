const std = @import("std");
const spin = @import("spin/lib.zig");
const status = @import("web/status.zig");
const proxy = @import("proxyverify.zig");

comptime {
    spin.handle(inboxScript);
}
pub fn main() void {
    std.debug.print("placeholder ", .{});
}

// one iteration from minimum script in which signature is checked
fn inboxScript(ally: std.mem.Allocator, ret: anytype, rcv: anytype) void {
    if (!proxy.verifySignature(ally, rcv)) {
        return status.dependency();
    }

    spin.redis.debugText(ally, rcv) catch {
        std.log.err("Inbox debug fault\x0A", .{});
        return status.internal();
    };

    ret.headers.append("Content-Type", "application/json") catch {
        std.log.err("Inbox header fault\x0A", .{});
    };

    status.ok();
}
