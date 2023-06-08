const std = @import("std");
const was = @import("wasi.zig");
const Allocator = std.mem.Allocator;

pub fn get(uri: []const u8, h: []was.Xtup) !void {
    const result = try send(.{
        .method = 0,
        .uri = uri,
        .headers = h,
        .js = "",
        //.params = params,
    });
    //std.debug.print("Outbound GET, {any}", .{result});
    std.log.debug("Outbound GET, {any}", .{result});
}

pub fn post(ally: Allocator, uri: []const u8, h: std.http.Headers, payload: anytype) ![]const u8 {
    var buf = std.ArrayList(u8).init(ally);
    defer buf.deinit();
    try std.json.stringify(payload, .{}, buf.writer());
    const js = try ally.dupeZ(u8, buf.items);

    //TODO refactor to accomodate generalized set of headers
    //h.append("content-type", "application/json");
    const literal_fld = "content-type";
    const literal_val = "application/json";
    const fld = was.Xstr{ .ptr = @constCast(literal_fld.ptr), .len = literal_fld.len };
    const val = was.Xstr{ .ptr = @constCast(literal_val.ptr), .len = literal_val.len };
    const ct_tup = was.Xtup{ .f0 = fld, .f1 = val };
    var bearer_tup: was.Xtup = undefined;
    const bearer_fld = "Authorization";
    if (h.getFirstEntry(bearer_fld)) |bearer| {
        const b_fld: [:0]u8 = try ally.dupeZ(u8, bearer.name);
        const b_val: [:0]u8 = try ally.dupeZ(u8, bearer.value);
        bearer_tup.f0 = was.Xstr{ .ptr = b_fld.ptr, .len = b_fld.len };
        bearer_tup.f1 = was.Xstr{ .ptr = b_val.ptr, .len = b_val.len };
    } else {
        const bearer_val = "verifier-proxy-bearer-token";
        bearer_tup.f0 = was.Xstr{ .ptr = @constCast(bearer_fld.ptr), .len = bearer_fld.len };
        bearer_tup.f1 = was.Xstr{ .ptr = @constCast(bearer_val.ptr), .len = bearer_val.len };
    }
    var arr = [_]was.Xtup{ ct_tup, bearer_tup };

    // uri (limit 255 characters) as C-string
    var curi: [255:0]u8 = undefined;
    if (uri.len >= curi.len) return error.PostUriMax;
    std.mem.copy(u8, curi[0..uri.len], uri);
    curi[uri.len] = 0;

    return send(.{
        .method = 1,
        .uri = curi[0..uri.len :0],
        .headers = &arr,
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

    const method = @bitCast(i32, @as(c_uint, req.method));

    const uri: [:0]const u8 = req.uri;
    const uri_ptr = @intCast(i32, @ptrToInt(uri.ptr));
    const uri_len = @bitCast(i32, @truncate(c_uint, uri.len));

    const headers: []was.Xtup = req.headers;
    const hdr_ptr = @intCast(i32, @ptrToInt(headers.ptr));
    const hdr_len = @bitCast(i32, @truncate(c_uint, headers.len));

    //const params = req.params.items;
    //const par_ptr = @intCast(i32, @ptrToInt(params.ptr));
    //const par_len = @bitCast(i32, @truncate(c_uint, params.len));

    //std.debug.print("\n?,payload: {s}", .{req.js});
    std.log.debug("\n?,payload: {s}", .{req.js});
    const js: [:0]const u8 = req.js;
    var js_enable: i32 = 0;
    var js_ptr: i32 = 0;
    var js_len: i32 = 0;
    if (js.len != 0) {
        js_enable = 1;
        js_ptr = @intCast(i32, @ptrToInt(js.ptr));
        js_len = @bitCast(i32, @truncate(c_uint, js.len));
    }

    const addr: i32 = @intCast(i32, @ptrToInt(&RET_AREA));
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
        addr,
    );

    const ptr = @intCast(usize, addr);
    const errcode = @as(c_uint, @intToPtr([*c]u8, ptr).*);
    if (errcode == 0) {
        const status = @as(c_uint, @intToPtr([*c]u16, ptr + @as(c_int, 4)).*);
        //std.debug.print("\n<,http.status: {d}", .{status});
        std.log.debug("\n<,http.status: {d}", .{status});

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
