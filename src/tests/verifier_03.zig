const std = @import("std");

const spin = @import("../spin/lib.zig");
const vrf = @import("../verify/verifier.zig");
const common = @import("common.zig");
const Allocator = std.mem.Allocator;

// show correctness of (input params to) SHA256 calculation
test "Mini signature base in the form of SHA256 sum" {
    const ally = std.testing.allocator;
    var raw = common.minRawHeaders(ally) catch @panic("OutofMem");
    defer raw.deinit();

    const sim_rcv_request = .{
        .method = .POST,
        .uri = "/foo?param=value&pet=dog",
        .headers = raw,
        .body = "{\x22hello\x22: \x22world\x22}",
    };
    try vrf.init(ally, raw);
    defer vrf.deinit();
    var hash: [32]u8 = undefined;
    // compute hash
    try vrf.sha256Base(sim_rcv_request, &hash);

    var minsum: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&minsum, "f29e22e3a108abc999f5b0ed27cdb461ca30cdbd3057efa170af52c83dfc0ca6");

    // With the headers specified, input base hash must be the sum:
    try std.testing.expectEqual(minsum, hash);
}
