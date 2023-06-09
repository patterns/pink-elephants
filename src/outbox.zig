const std = @import("std");
const spin = @import("spin/lib.zig");
const str = @import("web/strings.zig");
const status = @import("web/status.zig");
const vrf = @import("verify/verifier.zig");
const Allocator = std.mem.Allocator;
comptime {
    spin.handle(outboxScript);
}
pub fn main() void {
    std.debug.print("placeholder ", .{});
}

fn outboxScript(ally: Allocator, w: *spin.HttpResponse, rcv: anytype) void {
    if (!verifySignature(ally, rcv)) {
        // normally halt and respond with server-error
        ////return status.internal(w);
        std.debug.print("\nverify unsuccessful, capture info for troubleshooting", .{});
        // but we'll continue and capture info for troubleshooting
        // since our plan is to delegate processing to workers separately
    }
    // todo verify timestamp
    //TODO limit body content to 1MB
    var tree = str.toTree(ally, rcv.body) catch {
        std.log.err("JSON unexpected fault\n", .{});
        return status.unprocessable(w);
    };
    defer tree.deinit();

    // capture for now (add processing later)
    ////spin.redis.enqueue(ally, tree) catch {
    spin.redis.debugDetail(ally, .{ .rcv = rcv, .tree = tree }) catch {
        std.log.err("save fault\n", .{});
        return status.internal(w);
    };

    w.headers.put("Content-Type", "application/json") catch {
        std.log.err("response header, OutOfMem\n", .{});
    };

    status.ok(w);
}

// with outbox we expect the HTTP signature
// (we'll capture in any case to troubleshoot our implementation)
fn verifySignature(ally: Allocator, rcv: anytype) bool {
    vrf.prev2(ally, rcv.headers) catch {
        std.log.err("Preverify fault\n", .{});
        return false;
    };
    vrf.attachFetch(produceVerifierByProxy);

    var buffer: [512]u8 = undefined;
    var chan = std.io.fixedBufferStream(&buffer);
    vrf.fmtBase(rcv, chan.writer()) catch {
        std.log.err("Sig base input string fault\n", .{});
        return false;
    };

    var matching = vrf.bySigner(ally, chan.getWritten()) catch {
        std.log.err("Sig verify fault\n", .{});
        return false;
    };
    std.debug.print("\nLOOKHERE verify, {any}", .{matching});
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
    var fbs = std.io.fixedBufferStream(pem);
    return vrf.fromPEM(ally, fbs.reader());
}

fn pemFragment(ally: Allocator, js: []const u8) ![]const u8 {
    var parser = std.json.Parser.init(ally, .alloc_if_needed);
    defer parser.deinit();
    var tree = try parser.parse(js);
    defer tree.deinit();

    if (tree.root.object.get("publicKey")) |pubK| {
        //const id = pubK.object.get("id").?.string;
        //const owner = pubK.object.get("owner").?.string;
        const pem = pubK.object.get("publicKeyPem").?.string;
        return try ally.dupe(u8, pem);
    }

    return error.FragmentPublicKey;
}
