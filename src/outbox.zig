const std = @import("std");
const spin = @import("spin/lib.zig");
const status = @import("web/status.zig");
const proxy = @import("proxyverify.zig");

comptime {
    spin.handle(filterDelActivity);
}
pub fn main() void {
    std.debug.print("placeholder ", .{});
}

// one iteration from minimum script in which signature is checked
fn outboxScript(ally: std.mem.Allocator, ret: anytype, rcv: anytype) void {
    if (!proxy.verifySignature(ally, rcv)) {
        return status.dependency();
    }

    spin.redis.debugText(ally, rcv) catch {
        std.log.err("Outbox debug fault\x0A", .{});
        return status.internal();
    };

    ret.headers.append("Content-Type", "application/json") catch {
        std.log.err("Outbox header fault\x0A", .{});
    };

    status.ok();
}

// attempt to intercept delete activity and skip them
fn filterDelActivity(ally: std.mem.Allocator, ret: anytype, rcv: anytype) void {
    var parsed = std.json.parseFromSlice(std.json.Value, ally, rcv.body, .{}) catch {
        std.log.err("JSON parse fault on outbox body\x0A", .{});
        return status.internal();
    };
    defer parsed.deinit();
    const root = parsed.value;

    if (root.object.get("type")) |activity| {
        if (std.ascii.eqlIgnoreCase("Delete", activity.string)) {
            std.log.debug("RCV del activity, skipping.\x0A", .{});
            return status.ok();
        }
    }

    // branch to business as usual
    return outboxScript(ally, ret, rcv);
}
