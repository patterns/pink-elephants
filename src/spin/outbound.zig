const std = @import("std");
const was = @import("wasi.zig");
// requires 'allowed_http_hosts' component configuration

// obtain verifier key via proxy
//pub fn verifierByProxy(v: []const u8, proxy: []const u8) []const u8 {
//send(.{ .uri = "", .headers = , .body = });
//todo ?return raw pem (or public-key, pem is easier)
//    return "placeholder";
//}

pub fn get(uri: []const u8) !void {
    const headers: std.http.Headers = undefined;
    const params: std.ArrayList(was.WasiTuple) = undefined;
    const body: []u8 = undefined;
    const result = try send(.{
        .method = 0,
        .uri = uri,
        .headers = headers,
        .params = params,
        .body = body,
    });
    std.log.debug("outbound get, ");
}
pub fn post(uri: []const u8) !void {
    const headers: std.http.Headers = undefined;
    const params: std.ArrayList(was.WasiTuple) = undefined;
    const body: []u8 = undefined;
    const result = try send(.{
        .method = 1,
        .uri = uri,
        .headers = headers,
        .params = params,
        .body = body,
    });
    std.log.debug("outbound post, ");
}

//////////
// WASI C/interop

// host provided call signature
pub extern "wasi-outbound-http" fn request(i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32) void;

// static memory where host shares results
var RET_AREA: [32]u8 align(4) = std.mem.zeroes([32]u8);

// send "egress" traffic
pub fn send(req: anytype) !bool {
    //fn send(req: anytype) !*Response {
    //idea, use anon struct because egress is a "leaner" (loose) collection
    //      of fields; not the same as http.Request or spin.Request
    //      (what is the response struct?)

    var addr: i32 = @intCast(i32, @ptrToInt(&RET_AREA));
    const method = @intCast(i32, req.method);

    // uri
    const uri: []const u8 = req.uri;
    const uri_ptr = @intCast(i32, @ptrToInt(uri.ptr));
    const uri_len = @bitCast(i32, @truncate(c_uint, uri.len));

    const headers = was.toTuples(req.headers);
    const hdr_ptr = @intCast(i32, @ptrToInt(headers.ptr));
    const hdr_len = @bitCast(i32, @truncate(c_uint, headers.len));

    // params (expect tuples array)
    const params = req.params.items;
    const par_ptr = @intCast(i32, @ptrToInt(params.ptr));
    const par_len = @bitCast(i32, @truncate(c_uint, params.len));

    const body: []u8 = req.body;
    var bod_enable: i32 = 0;
    var bod_ptr: i32 = 0;
    var bod_len: i32 = 0;
    if (body.len != 0) {
        bod_enable = 1;
        bod_ptr = @intCast(i32, @ptrToInt(body.ptr));
        bod_len = @bitCast(i32, @truncate(c_uint, body.len));
    }

    // ask host to forward on our behalf
    request(
        method,
        uri_ptr,
        uri_len,
        hdr_ptr,
        hdr_len,
        par_ptr,
        par_len,
        bod_enable,
        bod_ptr,
        bod_len,
        addr,
    );

    const errcode_ptr = @intToPtr([*]u8, RET_AREA[0]);
    const errcode_val = @bitCast(i32, @as(c_uint, errcode_ptr.*));
    if (errcode_val == 0) {
        // TODO unmarshal response
        return true;
    } else {
        const error_info = @bitCast(i32, @as(c_uint, @intToPtr([*]u8, RET_AREA[4]).*));
        return false;
    }
}

pub const WASI_OUTBOUND_HTTP_HTTP_ERROR_SUCCESS = @as(c_int, 0);
pub const WASI_OUTBOUND_HTTP_HTTP_ERROR_DESTINATION_NOT_ALLOWED = @as(c_int, 1);
pub const WASI_OUTBOUND_HTTP_HTTP_ERROR_INVALID_URL = @as(c_int, 2);
pub const WASI_OUTBOUND_HTTP_HTTP_ERROR_REQUEST_ERROR = @as(c_int, 3);
pub const WASI_OUTBOUND_HTTP_HTTP_ERROR_RUNTIME_ERROR = @as(c_int, 4);
pub const WASI_OUTBOUND_HTTP_HTTP_ERROR_TOO_MANY_REQUESTS = @as(c_int, 5);
