//pub const std_options = struct { pub const log_level = .debug; };
pub fn main() void {
    @import("std").debug.print("replace with lib step?", .{});
}
const std = @import("std");
const spin = @import("spin/lib.zig");
const str = @import("web/strings.zig");
const status = @import("web/status.zig");
const vfr = @import("verifier/verifier.zig");
const phi = @import("web/phi.zig");
const Allocator = std.mem.Allocator;
const log = std.log;

//const custom_handler = blk:{
//    return spin.Runner.attachScript(struct {
fn demo_check(w: *spin.HttpResponse, r: *spin.SpinRequest) void {
    _ = r;
    status.dependency(w);
}
//    }.demo_check);
//    break :blk handler;
//};
comptime {
    spin.Keeper.attach(demo_check);
    //    const lib = @import("spin/lib.zig");
    //    @export(lib.guestHttpStart, .{.name = "handle-http-request"});
    //    @export(lib.canAbiRealloc, .{.name = "canonical_abi_realloc"});
    //    @export(lib.canAbiFree, .{.name = "canonical_abi_free"});
}

pub fn eval(ally: Allocator, w: *spin.HttpResponse, req: *spin.SpinRequest) void {
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
    ////spin.Redis.enqueue(allocator, logev) catch {
    spin.Redis.debugDetail(ally, .{ .tree = tree, .req = req }) catch {
        log.err("save failed", .{});
        return status.internal(w);
    };

    w.headers.put("Content-Type", "application/json") catch {
        log.err("inbox header, OutOfMem", .{});
    };

    status.ok(w);
}

fn unknownSignature(ally: Allocator, req: spin.SpinRequest) !bool {
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
