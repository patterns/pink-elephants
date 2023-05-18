const std = @import("std");
pub const std_options = struct {
    pub const log_level = .debug;
};
pub fn main() void {
    std.debug.print("placeholder ", .{});
}

comptime {
    @export(@import("spin/lib.zig").guestHttpStart, .{ .name = "handle-http-request", .linkage = .Strong });
    @export(@import("spin/lib.zig").canonicalAbiRealloc, .{ .name = "canonical_abi_realloc", .linkage = .Strong });
    @export(@import("spin/lib.zig").canonicalAbiFree, .{ .name = "canonical_abi_free", .linkage = .Strong });
}
const spn = @import("spin.zig");
const str = @import("web/strings.zig");
const status = @import("web/status.zig");
const config = spn.Config; //@import("spin/config.zig");
const redis = spn.Redis; //@import("spin/redis.zig");
const vfr = @import("verifier/verifier.zig");

const phi = @import("web/phi.zig");
const Allocator = std.mem.Allocator;
const log = std.log;

// implement interface
const Inbox = struct {
    pub fn eval(self: *Inbox, ally: Allocator, w: *spn.HttpResponse, req: *spn.SpinRequest) void {
        _ = self;
        const bad = unknownSignature(ally, req.*) catch true;

        if (bad) {
            return status.forbidden(w);
        }

        //TODO limit body content to 1MB
        var tree = str.toTree(ally, req.body) catch {
            log.err("unexpected json format\n", .{});
            return status.unprocessable(w);
        };
        defer tree.deinit();

        // capture for now (build processing later/next)
        ////redis.enqueue(allocator, logev) catch {
        redis.debugDetail(ally, .{ .tree = tree, .req = req }) catch {
            log.err("save failed", .{});
            return status.internal(w);
        };

        w.headers.put("Content-Type", "application/json") catch {
            log.err("inbox header, OutOfMem", .{});
        };

        status.ok(w);
    }
};

fn unknownSignature(ally: Allocator, req: spn.SpinRequest) !bool {
    const bad = true;

    var placeholder: phi.RawHeaders = undefined;
    var wrap = phi.HeaderList.init(ally, placeholder);

    try vfr.init(ally, placeholder);
    vfr.attachFetch(customVerifier);
    const base = try vfr.fmtBase(req, wrap);
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
