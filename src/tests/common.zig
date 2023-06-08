const std = @import("std");
const Allocator = std.mem.Allocator;

// simulate raw header fields
pub fn minRawHeaders(ally: Allocator) !std.http.Headers {
    var h2 = std.http.Headers.init(ally);
    try h2.append("host", "example.com");
    try h2.append("date", "Sun, 05 Jan 2014 21:31:40 GMT");
    try h2.append("content-type", "application/json");
    try h2.append("digest", "SHA-256=X48E9qOokqqrvdts8nOJRJN3OWDUoyWxBf7kbu9DBPE=");
    try h2.append("content-length", "18");

    try h2.append(
        "signature",
        "keyId=\x22Test\x22,algorithm=\x22rsa-sha256\x22,headers=\x22(request-target) host date\x22,signature=\x22qdx+H7PHHDZgy4y/Ahn9Tny9V3GP6YgBPyUXMmoxWtLbHpUnXS2mg2+SbrQDMCJypxBLSPQR2aAjn7ndmw2iicw3HMbe8VfEdKFYRqzic+efkb3nndiv/x1xSHDJWeSWkx3ButlYSuBskLu6kd9Fswtemr3lgdDEmn04swr2Os0=\x22",
    );

    var w = std.ArrayList(u8).init(ally);
    defer w.deinit();
    try h2.format("{s}", .{}, w.writer());

    return h2;
}

// simulate covered raw headers
pub fn regRawHeaders(ally: Allocator) !std.http.Headers {
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
