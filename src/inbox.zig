const std = @import("std");
const spin = @import("spin/lib.zig");
const str = @import("web/strings.zig");
const status = @import("web/status.zig");
const vfr = @import("verifier/verifier.zig");

const Allocator = std.mem.Allocator;
const log = std.log;
pub fn main() void {
    @import("std").debug.print("replace with lib step?", .{});
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

    ////try vfr.init(ally, r.headers);
    try vfr.prev2(ally, rcv.headers);
    vfr.attachFetch(customVerifier);
    const base = try vfr.fmtBase(rcv);
    _ = try vfr.bySigner(ally, base);

    // checks passed
    return !bad;
}

// need test cases for the httpsig input sequence
fn customVerifier(ally: Allocator, proxy: []const u8) !vfr.ParsedVerifier {
    _ = ally;
    if (proxy.len == 0) {
        return error.KeyProvider;
    }

    return vfr.ParsedVerifier{ .algo = undefined, .len = 0, .octet_string = undefined };
}
