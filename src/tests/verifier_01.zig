const std = @import("std");

const spin = @import("../spin/lib.zig");
const vrf = @import("../verify/verifier.zig");
const common = @import("common.zig");
const expectStr = std.testing.expectEqualStrings;

// exercise signature base reconstruction
test "Signature base input string mini" {
    const ally = std.testing.allocator;
    var raw = common.minRawHeaders(ally) catch @panic("OutofMem");
    defer raw.deinit();

    const sim_rcv_request = .{
        .method = .POST,
        .uri = "/foo?param=value&pet=dog",
        .body = "{\x22hello\x22: \x22world\x22}",
        .headers = raw,
    };
    var buffer: [512]u8 = undefined;
    var chan = std.io.fixedBufferStream(&buffer);
    // preverify
    try vrf.init(ally, raw);
    defer vrf.deinit();
    // recreate sig base input
    try vrf.fmtBase(sim_rcv_request, chan.writer());

    // With the headers specified, our expected signature base input string is:
    try expectStr(
        "(request-target): post /foo?param=value&pet=dog\x0Ahost: example.com\x0Adate: Sun, 05 Jan 2014 21:31:40 GMT",
        chan.getWritten(),
    );
}
