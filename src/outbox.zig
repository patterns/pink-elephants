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
    if (!verifySignature(ally, r)) {
        // normally halt and respond with server-error
        ////return status.internal(w);
        std.log.warn("verify unsucessful, capture info for troubleshooting", .{});
        // but we'll continue and capture info for troubleshooting
        // since our plan is to delegate processing to workers separately
    }
    // todo verify timestamp
    //TODO limit body content to 1MB
    var tree = str.toTree(ally, r.body) catch {
        std.log.err("JSON format unexpected fault", .{});
        return status.unprocessable(w);
    };
    defer tree.deinit();

    // capture for now (add processing later)
    spin.redis.enqueue(ally, tree) catch {
        std.log.err("save fault", .{});
        return status.internal(w);
    };

    w.headers.put("Content-Type", "application/json") catch {
        std.log.err("response header, OutOfMem", .{});
    };

    status.ok(w);
}

// with outbox we expect the HTTP signature
// (we'll capture in any case to troubleshoot our implementation)
fn verifySignature(ally: Allocator, r: *spin.Request) bool {
    var wrap = phi.HeaderList.init(ally, r.headers);
    wrap.catalog() catch {
        std.log.err("Wrap raw headers fault", .{});
        return false;
    };
    vfr.init(ally, r.headers) catch {
        std.log.err("Init verifier fault", .{});
        return false;
    };
    vfr.attachFetch(produceVerifierByProxy);
    const base = vfr.fmtBase(r.*, wrap) catch {
        std.log.err("Sig base input string fault", .{});
        return false;
    };
    var matching = vfr.bySigner(ally, base) catch {
        std.log.err("Sig verify fault", .{});
        return false;
    };
    std.log.info("LOOKHERE verify, {any}", .{matching});
    return matching;
}

// custom fetch to retrieve the verifier
// via the known allowed-server declared in configuration
fn produceVerifierByProxy(ally: Allocator, keyProv: []const u8) !vfr.ParsedVerifier {
    // conf setting for proxy
    const proxy_uri = spin.config.verifierProxyUri() orelse "http://localhost:8000";
    // conf setting for proxy bearer token
    const proxy_bearer = spin.config.verifierProxyBearer() orelse "proxy-bearer-token";

    const literal = "Authorization";
    const fld = spin.wasi.Xstr{ .ptr = @ptrToInt(&literal), .len = literal.len };
    const val = spin.wasi.Xstr{ .ptr = @ptrToInt(&proxy_bearer), .len = proxy_bearer.len };
    var h = [_]spin.wasi.Xtup{spin.wasi.Xtup{ .f0 = fld, .f1 = val }};

    // key provider JSON to specify lookup origin of verifier
    var b = std.ArrayList(u8).init(ally);
    defer b.deinit();
    try b.appendSlice("{\"locator\": \"");
    try b.appendSlice(keyProv);
    try b.appendSlice("\"}");

    // make egress trip to proxy
    const res = try spin.outbound.post(proxy_uri, &h, b.items);
    std.log.info("Proxy response, {s}\n", .{res});

    const pem = try std.json.parseFromSlice(fragment, ally, res, .{});
    defer std.json.parseFree(fragment, ally, pem);
    var fbs = std.io.fixedBufferStream(pem.publicKey.publicKeyPem);
    return vfr.fromPEM(ally, fbs.reader());
}

// ?will json parse ignore input fields that are not listed here
const fragment = struct {
    publicKey: struct {
        id: []const u8,
        owner: []const u8,
        publicKeyPem: []const u8,
    },
};
