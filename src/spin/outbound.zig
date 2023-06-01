const std = @import("std");
const was = @import("wasi.zig");
const Allocator = std.mem.Allocator;

// requires 'allowed_http_hosts' component configuration

pub fn get(uri: []const u8, h: std.ArrayList(was.Xtup)) !void {
    //const params: std.ArrayList(was.Xtup) = undefined ;

    const result = try send(.{
        .method = 0,
        .uri = uri,
        .headers = h.items,
        .body = "",
        //.params = params,
    });

    std.log.info("Outbound GET, {any}", .{result});
}

pub fn post(uri: []const u8, h: []was.Xtup, body: []const u8) ![]const u8 {
    //todo accept std.http.Headers and convert to []was.Xtup
    return send(.{
        .method = 1,
        .uri = uri,
        .headers = h,
        .body = body,
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

    const method = @as(i32, req.method);

    const uri: []const u8 = req.uri;
    const uri_ptr = @intCast(i32, @ptrToInt(uri.ptr));
    const uri_len = @bitCast(i32, @truncate(c_uint, uri.len));

    const headers: []was.Xtup = req.headers;
    const hdr_ptr = @intCast(i32, @ptrToInt(headers.ptr));
    const hdr_len = @bitCast(i32, @truncate(c_uint, headers.len));

    //const params = req.params.items;
    //const par_ptr = @intCast(i32, @ptrToInt(params.ptr));
    //const par_len = @bitCast(i32, @truncate(c_uint, params.len));

    const body: []const u8 = req.body;
    var bod_enable: i32 = 0;
    var bod_ptr: i32 = 0;
    var bod_len: i32 = 0;
    if (body.len != 0) {
        bod_enable = 1;
        bod_ptr = @intCast(i32, @ptrToInt(body.ptr));
        bod_len = @bitCast(i32, @truncate(c_uint, body.len));
    }

    var addr: i32 = @intCast(i32, @ptrToInt(&RET_AREA));
    // ask host to forward on our behalf
    request(
        method,
        uri_ptr,
        uri_len,
        hdr_ptr,
        hdr_len,
        0,
        0, ////par_ptr, par_len,
        bod_enable,
        bod_ptr,
        bod_len,
        addr,
    );

    const ptr = @intCast(usize, addr);
    const errcode = @as(c_uint, @intToPtr([*c]u8, ptr).*);
    if (errcode == 0) {
        const status = @as(c_uint, @intToPtr([*c]u16, ptr + @as(c_int, 4)).*);
        std.log.info("Response status {d}", .{status});

        const has_payload = @as(c_uint, @intToPtr([*c]u8, ptr + @as(c_int, 20)).*);
        if (has_payload == 0) return "";
        // unmarshal response content
        const pl_ptr = @intToPtr([*c]u8, @intCast(usize, @intToPtr([*c]i32, ptr + 24).*));
        const pl_len = @bitCast(usize, @as(c_long, @intToPtr([*c]i32, ptr + @as(c_int, 28)).*));

        return pl_ptr[0..pl_len];
    }

    var detail: []const u8 = undefined;
    const err_grp = @as(c_uint, @intToPtr([*c]u8, ptr + @as(c_int, 4)).*);
    switch (err_grp) {
        1 => detail = "destination not allowed",
        2 => detail = "invalid url",
        3 => detail = "request error",
        4 => detail = "runtime error",
        5 => detail = "too many requests",
        else => detail = "unreachable-else",
    }
    std.log.err("HTTP outbound, {s}", .{detail});
    return error.OutboundPost;
}
