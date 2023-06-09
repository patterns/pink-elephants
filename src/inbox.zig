const std = @import("std");
const spin = @import("spin/lib.zig");
const str = @import("web/strings.zig");
const status = @import("web/status.zig");
const vrf = @import("verify/verifier.zig");

const Allocator = std.mem.Allocator;
const log = std.log;
pub fn main() void {
    std.debug.print("replace with lib step?", .{});
}
comptime {
    spin.handle(inboxScript);
}

fn inboxScript(ally: Allocator, w: *spin.HttpResponse, rcv: anytype) void {
    const bad = unknownSignature(ally, rcv) catch true;

    if (bad) {
        //todo worth logging in the early tests to see common failures?
        return status.forbidden(w);
    }

    //TODO limit body content to 1MB
    var tree = str.toTree(ally, rcv.body) catch {
        log.err("unexpected json format\n", .{});
        return status.unprocessable(w);
    };
    defer tree.deinit();

    // capture for now (build processing later/next)
    ////spin.redis.enqueue(allocator, logev) catch {
    spin.redis.debugDetail(ally, .{ .tree = tree, .rcv = rcv }) catch {
        log.err("save failed", .{});
        return status.internal(w);
    };

    w.headers.put("Content-Type", "application/json") catch {
        log.err("inbox header, OutOfMem", .{});
    };

    status.ok(w);
}

fn unknownSignature(ally: Allocator, rcv: anytype) !bool {
    const bad = true;

    ////try vrf.init(ally, r.headers);
    try vrf.prev2(ally, rcv.headers);
    vrf.attachFetch(customVerifier);

    var buffer: [512]u8 = undefined;
    var chan = std.io.fixedBufferStream(&buffer);
    try vrf.fmtBase(rcv, chan.writer());
    _ = try vrf.bySigner(ally, chan.getWritten());

    // checks passed
    return !bad;
}

// need test cases for the httpsig input sequence
fn customVerifier(ally: Allocator, proxy: []const u8) !vrf.ParsedVerifier {
    _ = ally;
    if (proxy.len == 0) {
        return error.KeyProvider;
    }

    return vrf.ParsedVerifier{ .algo = undefined, .len = 0, .octet_string = undefined };
}
