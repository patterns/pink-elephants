const std = @import("std");
const was = @import("wasi.zig");
const Allocator = std.mem.Allocator;

pub fn get(uri: []const u8, h: []was.Xfield) !void {
    const result = try send(.{
        .method = 0,
        .uri = uri,
        .headers = h,
        .js = "",
        //.params = params,
    });

    std.log.debug("Outbound.get, {any}\x0A", .{result});
}

pub fn post(ally: Allocator, uri: []const u8, h: std.http.Headers, payload: anytype) ![]const u8 {
    var buf = std.ArrayList(u8).init(ally);
    defer buf.deinit();
    try std.json.stringify(payload, .{}, buf.writer());
    const js = try ally.dupeZ(u8, buf.items);

    //TODO refactor to accomodate generalized set of headers
    var single_use = std.http.Headers.init(ally);
    defer single_use.deinit();
    try single_use.append("content-type", "application/json");

    const bearer_fld = "Authorization";
    if (h.getFirstEntry(bearer_fld)) |bearer| {
        try single_use.append(bearer.name, bearer.value);
    } else {
        try single_use.append(bearer_fld, "verifier-proxy-bearer-token");
    }

    const arr = try was.shipFields(ally, single_use);

    // uri (limit 255 characters) as C-string
    var curi: [255:0]u8 = undefined;
    if (uri.len >= curi.len) return error.PostUriMax;
    std.mem.copy(u8, curi[0..uri.len], uri);
    curi[uri.len] = 0;

    return send(.{
        .method = 1,
        .uri = curi[0..uri.len :0],
        .headers = arr,
        .js = js,
        //.params = params,
    });
}

//////////
// WASI C/interop

// host provided call signature
pub extern "wasi-outbound-http" fn request(i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32) void;

// static memory where host shares results
var RET_AREA: [32]u8 align(4) = std.mem.zeroes([32]u8);

// send "egress" traffic
pub fn send(req: anytype) ![]const u8 {
    // anon struct because egress is a leaner (loose) collection
    // of fields; not the same as http.Request or spin.Request
    // (make the response also anon struct?)

    const method: i32 = @bitCast(@as(c_uint, req.method));

    const uri: [:0]const u8 = req.uri;
    const up: usize = @intFromPtr(uri.ptr);
    const uri_ptr: i32 = @intCast(up);
    const uri_len: i32 = @intCast(uri.len);

    const headers: []was.Xfield = req.headers;
    const hp: usize = @intFromPtr(headers.ptr);
    const hdr_ptr: i32 = @intCast(hp);
    const hdr_len: i32 = @intCast(headers.len);

    //const params = req.params.items;
    //const par_ptr = @intCast(i32, @ptrToInt(params.ptr));
    //const par_len = @bitCast(i32, @truncate(c_uint, params.len));

    const js: [:0]const u8 = req.js;
    var js_enable: i32 = 0;
    var js_ptr: i32 = 0;
    var js_len: i32 = 0;
    if (js.len != 0) {
        js_enable = 1;
        const jp: usize = @intFromPtr(js.ptr);
        js_ptr = @intCast(jp);
        js_len = @intCast(js.len);
    }

    const ad: usize = @intFromPtr(&RET_AREA);
    const address: i32 = @intCast(ad);
    // ask host to forward on our behalf
    request(
        method,
        uri_ptr,
        uri_len,
        hdr_ptr,
        hdr_len,
        0,
        0, ////par_ptr, par_len,
        js_enable,
        js_ptr,
        js_len,
        address,
    );

    const code_ptr: [*c]u8 = @ptrFromInt(ad);
    const errcode: u8 = @intCast(code_ptr.*);

    if (errcode == 0) {
        const status_ptr: [*c]u16 = @ptrFromInt(ad + 4);
        const status: u16 = @intCast(status_ptr.*);
        std.log.debug("Outbound.post, {d}\x0A", .{status});

        const flag_ptr: [*c]u8 = @ptrFromInt(ad + 20);
        const has_payload: u16 = @intCast(flag_ptr.*);
        if (has_payload == 0) return "";

        // unmarshal response content
        const content_ptr: [*c]i32 = @ptrFromInt(ad + 24);
        const max_ptr: [*c]i32 = @ptrFromInt(ad + 28);
        const pp: usize = @intCast(content_ptr.*);
        const pl_ptr: [*c]u8 = @ptrFromInt(pp);
        const pl_len: usize = @intCast(max_ptr.*);

        return pl_ptr[0..pl_len];
    }

    const err_ptr: [*c]u8 = @ptrFromInt(ad + 4);
    const err_grp: u8 = @intCast(err_ptr.*);
    var detail: []const u8 = undefined;
    switch (err_grp) {
        1 => detail = "destination not allowed",
        2 => detail = "invalid url",
        3 => detail = "request error",
        4 => detail = "runtime error",
        5 => detail = "too many requests",
        else => detail = "unreachable-else",
    }
    std.log.err("HTTP outbound, {s}\x0A", .{detail});
    return error.OutboundPost;
}
