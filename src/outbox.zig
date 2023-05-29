const std = @import("std");
const spin = @import("spin/lib.zig");
const str = @import("web/strings.zig");
const status = @import("web/status.zig");
const phi = @import("web/phi.zig");
const vfr = @import("verifier/verifier.zig");

const Allocator = std.mem.Allocator;
comptime {
    spin.handle(outboxScript);
}
pub fn main() void {
    std.debug.print("placeholder ", .{});
}
//todo std.http.Headers should supercede our array-list?
fn outboxScript(ally: Allocator, w: *spin.HttpResponse, r: *spin.Request) void {
    var wrap = phi.HeaderList.init(ally, r.headers);
    wrap.catalog() catch {
        std.log.err("Wrap raw headers failed\n", .{});
        return status.internal(w);
    };
    vfr.init(ally, r.headers) catch {
        std.log.err("Init verifier failed\n", .{});
        return status.internal(w);
    };
    vfr.attachFetch(produceVerifierByProxy);
    const base = vfr.fmtBase(r.*, wrap) catch {
        std.log.err("Sig base input string failed\n", .{});
        return status.internal(w);
    };
    var matching = vfr.bySigner(ally, base) catch {
        std.log.err("Sig verify failed\n", .{});
        return status.internal(w);
    };
    std.log.info("verify, {any}", .{matching});

    // todo verify timestamp
    //TODO limit body content to 1MB
    var tree = str.toTree(ally, r.body) catch {
        std.log.err("unexpected json format\n", .{});
        return status.unprocessable(w);
    };
    defer tree.deinit();

    // capture for now (add processing later)
    spin.redis.enqueue(ally, tree) catch {
        std.log.err("save failed", .{});
        return status.internal(w);
    };

    w.headers.put("Content-Type", "application/json") catch {
        std.log.err("response header, OutOfMem", .{});
    };

    status.ok(w);
}

// retrieve verifier via the configuration known allowed-server
fn produceVerifierByProxy(ally: Allocator, keyProv: []const u8) !vfr.ParsedVerifier {
    // conf setting for proxy
    const proxy_uri = spin.config.verifierProxyUri();
    // conf setting for proxy bearer token
    const proxy_bearer = spin.config.verifierProxyBearer() orelse "proxy-bearer-token";
    var h = std.http.Headers.init(ally);
    defer h.deinit();
    try h.append("Authorization", proxy_bearer);

    // key provider JSON to specify lookup of verifier (public key)
    const body = try std.fmt.allocPrint(ally, "{\"locator\": \"{s}\"}", .{keyProv});

    const response = spin.outbound.post(proxy_uri, h, body);
    std.log.info("to-be-json-parsed, {any}", .{response});
    //TODO parse json response
}
