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

fn inboxScript(ally: std.mem.Allocator, w: *spin.HttpResponse, rcv: anytype) void {
    if (!proxy.verifySignature(ally, rcv)) {
        // normally halt and respond with server-error
        ////return status.internal(w);
        std.debug.print("capture for troubleshooting", .{});
        // but we'll continue and capture info for troubleshooting
        // since our plan is to delegate processing to workers separately
    }
    // todo verify timestamp
    //TODO limit body content to 1MB
    var tree = str.toTree(ally, rcv.body) catch {
        std.log.err("JSON unexpected fault\x0A", .{});
        return status.unprocessable(w);
    };
    defer tree.deinit();

    // capture for now (add processing later)
    ////spin.redis.enqueue(ally, tree) catch {
    spin.redis.debugDetail(ally, .{ .rcv = rcv, .tree = tree }) catch {
        std.log.err("save fault\x0A", .{});
        return status.internal(w);
    };

    w.headers.put("Content-Type", "application/json") catch {
        std.log.err("response header, OutOfMem\x0A", .{});
    };

    status.ok(w);
}
