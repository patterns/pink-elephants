const std = @import("std");

const spin = @import("../spin/lib.zig");
const vrf = @import("../verify/verifier.zig");
const meth = @import("../web/method.zig");
const common = @import("common.zig");
const Allocator = std.mem.Allocator;

// show correctness of (input params to) SHA256 calculation
test "Reg signature base in the form of SHA256 sum" {
    const ally = std.testing.allocator;
    // headers to cover host,date,digest,content-type,content-length
    var raw = common.regRawHeaders(ally) catch @panic("OutofMem");
    defer raw.deinit();

    var sim_rcv_request = .{
        .method = meth.Verb.post,
        .uri = "/foo?param=value&pet=dog",
        .headers = raw,
        .body = "{\x22hello\x22: \x22world\x22}",
    };
    try vrf.init(ally, raw);
    defer vrf.deinit();
    var hash: [32]u8 = undefined;
    // perform calculation
    try vrf.sha256Base(sim_rcv_request, &hash);

    var regsum: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&regsum, "53CD4050FF72E3A6383091186168F3DF4CA2E6B3A77CBED60A02BA00C9CD8078");

    // With the headers specified, our signature base must be sum:
    try std.testing.expectEqual(regsum, hash);
}
