const std = @import("std");
const spin = @import("spin/lib.zig");
const str = @import("web/strings.zig");
const status = @import("web/status.zig");
const vrf = @import("verify/verifier.zig");
const proxy = @import("proxyverify.zig");
comptime {
    spin.handle(inboxScript);
}
pub fn main() void {
    std.debug.print("placeholder ", .{});
}

fn inboxScript(ally: std.mem.Allocator, ret: anytype, rcv: anytype) void {
    //TODO limit body content to 1MB
    var tree = str.toTree(ally, rcv.body) catch {
        std.log.err("JSON unexpected fault\x0A", .{});
        return status.unprocessable();
    };
    defer tree.deinit();
    // todo verify timestamp
    if (!proxy.verifySignature(ally, rcv)) {
        spin.redis.debugDetail(ally, .{ .rcv = rcv, .tree = tree }) catch {
            std.log.err("Detail fault\x0A", .{});
        };
        return status.internal();
    }

    // capture for now (add processing later)
    spin.redis.enqueue(ally, tree) catch {
        std.log.err("Enqueue fault\x0A", .{});
        return status.internal();
    };

    ret.headers.append("Content-Type", "application/json") catch {
        std.log.err("response header, OutOfMem\x0A", .{});
    };

    status.ok();
}
