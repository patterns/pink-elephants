const std = @import("std");

const spin = @import("../spin/lib.zig");
const vfr = @import("../verifier/verifier.zig");
const common = @import("common.zig");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const expectErr = std.testing.expectError;
const expectStr = std.testing.expectEqualStrings;

// exercise signature base reconstruction
test "Signature base input string reg" {
    const ally = std.testing.allocator;
    // headers to cover host,date,digest,content-type,content-length
    var raw = common.regRawHeaders(ally) catch @panic("OutofMem");
    defer raw.deinit();

    var sim_rcv_request = .{
        .method = spin.http.Verb.post,
        .uri = "/foo?param=value&pet=dog",
        .headers = raw,
        .body = "{\x22hello\x22: \x22world\x22}",
    };
    try vfr.prev2(ally, raw);
    defer vfr.deinit();
    // format sig base input
    const base = try vfr.fmtBase(sim_rcv_request);

    // With the headers specified, our expected signature base input string is:
    try expectStr(
        "(request-target): post /foo?param=value&pet=dog\x0Ahost: example.com\x0Adate: Sun, 05 Jan 2014 21:31:40 GMT\x0Acontent-type: application/json\ndigest: SHA-256=X48E9qOokqqrvdts8nOJRJN3OWDUoyWxBf7kbu9DBPE=\x0Acontent-length: 18",

        base,
    );
}
