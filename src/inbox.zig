const std = @import("std");
const spin = @import("spin/lib.zig");
const str = @import("web/strings.zig");
const status = @import("web/status.zig");
const vfr = @import("verifier/verifier.zig");
const phi = @import("web/phi.zig");
const Allocator = std.mem.Allocator;
const log = std.log;
pub fn main() void {
    @import("std").debug.print("replace with lib step?", .{});
}
comptime {
    spin.handle(inboxScript);
}

fn inboxScript(ally: Allocator, w: *spin.HttpResponse, r: *spin.Request) void {
    const bad = unknownSignature(ally, r.*) catch true;

    if (bad) {
        //todo worth logging in the early tests to see common failures?
        return status.forbidden(w);
    }

    //TODO limit body content to 1MB
    var tree = str.toTree(ally, r.body) catch {
        log.err("unexpected json format\n", .{});
        return status.unprocessable(w);
    };
    defer tree.deinit();

    // capture for now (build processing later/next)
    ////spin.redis.enqueue(allocator, logev) catch {
    spin.redis.debugDetail(ally, .{ .tree = tree, .req = r }) catch {
        log.err("save failed", .{});
        return status.internal(w);
    };

    w.headers.put("Content-Type", "application/json") catch {
        log.err("inbox header, OutOfMem", .{});
    };

    status.ok(w);
}

fn unknownSignature(ally: Allocator, r: spin.Request) !bool {
    const bad = true;

    var placeholder: phi.RawHeaders = undefined;
    var wrap = phi.HeaderList.init(ally, placeholder);

    try vfr.init(ally, placeholder);
    vfr.attachFetch(customVerifier);
    const base = try vfr.fmtBase(r, wrap);
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
