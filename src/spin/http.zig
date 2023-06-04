const std = @import("std");

const wasi = @import("wasi.zig");
const Allocator = std.mem.Allocator;

// request.method
pub fn method() HttpMethod {
    const cm = context.get("method");
    switch (cm) {
        "get" => return 0,
        "post" => return 1,
        else => unreachable,
    }
}
// request.body
pub fn body() [:0]u8 {
    return context.get("body").?;
}
// request.uri
pub fn uri() [:0]u8 {
    return context.get("uri").?;
}
// request.headers
pub fn headers() std.http.Headers {
    return context.h();
}

//TODO auth params (leaf nodes of signature header)

// request context
pub fn init(ally: Allocator, state: anytype) void {
    context.init(ally, state);
}
pub fn deinit() void {
    context.deinit();
}

// namespace nesting (to overlay request fields)
const context = blk: {
    // static variables
    var raw: std.BoundedArray(std.http.Field, 128);
    var map: std.StringHashMap([:0]u8);
    var hx2: std.http.Headers;

    const keeper = struct {
        // accept mem addresses from C/interop
        fn init(ally: Allocator, state: anytype) !void {
            const method: i32 = state.method;
            const uri_ad: WasiAddr = state.uri_ad;
            const uri_len: i32 = state.uri_len;
            const hdr_ad: WasiAddr = state.hdr_ad;
            const hdr_len: i32 = state.hdr_len;
            //const paramAddr: WasiAddr = state.paramAddr;
            //const paramLen: i32 = state.paramLen;
            const bod_enable: i32 = state.bod_enable;
            const bod_ad: WasiAddr = state.bod_ad;
            const bod_len: i32 = state.bod_len;

            map = std.StringHashMap([:0]u8).init(ally);
            const cu = try wasi.xdata.dupeZ(ally, uri_ad, uri_len);
            try map.put("uri", cu);

            var cb: [:0]u8 = "";
            if (bod_enable == 1) {
                cb = wasi.xdata.dupeZ(ally, bod_ad, bod_len);
            }
            try map.put("body", cb);

            var cm: [:0]u8 = undefined;
            switch (method) {
                0 => cm = "get",
                1 => cm = "post",
                else => unreachable,
            }
            try map.put("method", cm);

            try raw.fromSlice(try wasi.xslice(ally, hdr_ad, hdr_len));
            hx2 = std.http.Headers.init(ally);
            //var _params = wasi.xlist(ally, paramAddr, paramLen)
        }
        fn deinit() void {
            map.deinit();
            hx2.deinit();
        }
        // headers overlay on raw
        fn h() std.http.Headers {
            if (!hx2.contains("content-type")) {
                // if we didn't initialize, do that first
                var i = 0;
                while (i < raw.len) : (i += 1) {
                    const ent = raw.get(i);
                    try hx2.append(ent.name, ent.value);
                }
            }
            return hx2;
        }
        // general way to access 80% fields (minimal interface of request)
        fn get(comptime name: []const u8) ?[:0]u8 {
            return map.get(name);
        }
    };
    break :blk keeper;
};

// C/interop address
pub const WasiAddr = i32;
// "anon" struct just for address to tuple C/interop
const WasiStr = extern struct { ptr: [*c]u8, len: usize };
const WasiTuple = extern struct { f0: WasiStr, f1: WasiStr };

/// HTTP method verb.
pub const HttpMethod = u8;
