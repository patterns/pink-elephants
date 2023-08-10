const std = @import("std");
const spin = @import("spin/lib.zig");
const vrf = @import("verify/verifier.zig");
const Allocator = std.mem.Allocator;

// high-level HTTP signature verify routine for in/outbox
pub fn verifySignature(ally: Allocator, rcv: anytype) bool {
    vrf.init(ally, rcv.headers) catch {
        std.log.err("Preverify fault\x0A", .{});
        return false;
    };

    vrf.attachFetch(produceVerifierByProxy);

    // conf setting for the host header rewrite
    const httpsig_origin = spin.config.httpsigOrigin() orelse "localhost";
    const httpsig_gateway = spin.config.httpsigGateway() orelse "load-balancer";
    vrf.rewriteRule(httpsig_origin, httpsig_gateway);

    var buffer: [512]u8 = undefined;
    var chan = std.io.fixedBufferStream(&buffer);
    vrf.fmtBase(rcv, chan.writer()) catch {
        std.log.err("Sig base input string fault\x0A", .{});
        return false;
    };

    var matching = vrf.bySigner(ally, chan.getWritten()) catch {
        std.log.err("Sig verify fault\x0A", .{});
        return false;
    };

    return matching;
}

// custom fetch to retrieve the verifier
// via the known allowed-server declared in configuration
fn produceVerifierByProxy(ally: Allocator, key_provider: []const u8) !vrf.ParsedVerifier {
    // conf setting for proxy
    const proxy_uri = spin.config.verifierProxyUri() orelse "http://localhost:8000";
    // conf setting for proxy bearer token
    const proxy_bearer = spin.config.verifierProxyBearer() orelse "proxy-bearer-token";
    // minimal headers that we *pre-agree* are required by the proxy
    var h = std.http.Headers.init(ally);
    defer h.deinit();
    try h.append("Authorization", proxy_bearer);

    // key provider JSON to specify lookup origin of verifier
    const payload = .{ .locator = key_provider };

    // make egress trip to proxy
    const js = try spin.outbound.post(ally, proxy_uri, h, payload);

    const pem = try pemFragment(ally, js);
    defer ally.free(pem);
    std.log.debug("<< pemFrag {s}\x0A", .{pem});

    var fbs = std.io.fixedBufferStream(pem);
    return vrf.fromPEM(ally, fbs.reader());
}

// read the PEM section from the actor JSON
fn pemFragment(ally: Allocator, js: []const u8) ![]const u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, ally, js, .{});
    defer parsed.deinit();
    const root = parsed.value;

    if (root.object.get("publicKey")) |pubK| {
        //const id = pubK.object.get("id").?.string;
        //const owner = pubK.object.get("owner").?.string;
        const pem = pubK.object.get("publicKeyPem").?.string;
        return try ally.dupe(u8, pem);
    }

    return error.FragmentPublicKey;
}
