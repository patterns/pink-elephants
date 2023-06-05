const std = @import("std");
const spin = @import("spin/lib.zig");
const str = @import("web/strings.zig");
const status = @import("web/status.zig");
//const phi = @import("web/phi.zig");
const vfr = @import("verifier/verifier.zig");

const Allocator = std.mem.Allocator;
comptime {
    spin.handle(outboxScript);
}
pub fn main() void {
    std.debug.print("placeholder ", .{});
}
//todo std.http.Headers should supercede our array-list?
fn outboxScript(ally: Allocator, w: *spin.HttpResponse, r: anytype) void {
    if (!verifySignature(ally, r)) {
        // normally halt and respond with server-error
        ////return status.internal(w);
        std.debug.print("\nverify unsucessful, capture info for troubleshooting", .{});
        // but we'll continue and capture info for troubleshooting
        // since our plan is to delegate processing to workers separately
    }
    // todo verify timestamp
    //TODO limit body content to 1MB
    var tree = str.toTree(ally, r.body) catch {
        std.log.err("JSON unexpected fault", .{});
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
fn verifySignature(ally: Allocator, r: anytype) bool {
    //var wrap = phi.HeaderList.init(ally, r.headers);
    //wrap.catalog() catch {
    //vfr.init(ally, r.headers) catch {
    //        std.log.err("Init verifier fault", .{});
    //        return false;
    //};
    // * SPROUT
    //   By this point, preverify was run to populate the
    //   leaf nodes for the 'signature' header. So for h2
    //   we want to mirror the nodes as "prev2".
    vfr.prev2(ally, r.headers) catch {
        std.log.err("Preverify2 fault", .{});
        return false;
    };

    vfr.attachFetch(produceVerifierByProxy);
    //const base = vfr.fmtBase(r.*, wrap) catch {
    //        std.log.err("Sig base input string fault", .{});
    //        return false;
    //};
    const base2 = vfr.fmtBase2(r, r.headers) catch {
        std.log.err("fmt base2 fault", .{});
        return false;
    };
    std.debug.print("\n?,base2: {s}", .{base2});

    var matching = vfr.bySigner(ally, base2) catch {
        std.log.err("Sig verify fault", .{});
        return false;
    };
    std.debug.print("\nLOOKHERE verify, {any}", .{matching});
    return matching;
}

// custom fetch to retrieve the verifier
// via the known allowed-server declared in configuration
fn produceVerifierByProxy(ally: Allocator, key_provider: []const u8) !vfr.ParsedVerifier {
    // conf setting for proxy
    const proxy_uri = spin.config.verifierProxyUri() orelse "http://localhost:8000";
    // conf setting for proxy bearer token
    const proxy_bearer = spin.config.verifierProxyBearer() orelse "proxy-bearer-token";

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
    return vfr.fromPEM(ally, fbs.reader());
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
