const std = @import("std");

const spin = @import("../spin/lib.zig");
const vfr = @import("../verifier/verifier.zig");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const expectErr = std.testing.expectError;
const expectStr = std.testing.expectEqualStrings;

// exercise signature base reconstruction
test "Signature base input string reg" {
    const ally = std.testing.allocator;
    // headers to cover host,date,digest,content-type,content-length
    var raw = regRawHeaders(ally) catch @panic("OutofMem");
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

// simulate covered raw headers
fn regRawHeaders(ally: Allocator) !std.http.Headers {
    var h2 = std.http.Headers.init(ally);
    try h2.append("host", "example.com");
    try h2.append("date", "Sun, 05 Jan 2014 21:31:40 GMT");
    try h2.append("content-type", "application/json");
    try h2.append("digest", "SHA-256=X48E9qOokqqrvdts8nOJRJN3OWDUoyWxBf7kbu9DBPE=");
    try h2.append("content-length", "18");

    try h2.append(
        "signature",
        "keyId=\x22Test\x22,algorithm=\x22rsa-sha256\x22,headers=\x22(request-target) host date content-type digest content-length\x22,signature=\x22qdx+H7PHHDZgy4y/Ahn9Tny9V3GP6YgBPyUXMmoxWtLbHpUnXS2mg2+SbrQDMCJypxBLSPQR2aAjn7ndmw2iicw3HMbe8VfEdKFYRqzic+efkb3nndiv/x1xSHDJWeSWkx3ButlYSuBskLu6kd9Fswtemr3lgdDEmn04swr2Os0=\x22",
    );

    return h2;
}
