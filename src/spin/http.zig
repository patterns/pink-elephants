const std = @import("std");
const wasi = @import("wasi.zig");
const meth = @import("../web/method.zig");
const Allocator = std.mem.Allocator;

// request.method
pub fn method() meth.Verb {
    ////const cm = context.get("method").?;
    ////const en = meth.Verb.fromDescr(cm);
    return context.en;
}
// request.body
pub fn body() [:0]const u8 {
    ////return context.get("body").?;
    return context.cb;
}
// request.uri
pub fn uri() [:0]const u8 {
    ////return context.get("uri").?;
    return context.cu;
}
// request.headers
pub fn headers() std.http.Headers {
    // read-only
    return context.h;
}

// the request received
pub fn init(ally: Allocator, state: anytype) !void {
    try context.init(ally, state);
}
pub fn deinit() void {
    context.deinit();
}

// namespace nesting (to overlay received fields)
const context = struct {
    // static variables
    var h: std.http.Headers = undefined;
    var cu: [:0]const u8 = undefined;
    var cb: [:0]const u8 = undefined;
    var en: meth.Verb = undefined;

    // accept mem addresses from C/interop
    fn init(ally: Allocator, state: anytype) !void {
        const verb: i32 = state.method;
        const uri_ptr: WasiPtr = state.uri_ptr;
        const uri_len: i32 = state.uri_len;
        const hdr_ptr: WasiPtr = state.hdr_ptr;
        const hdr_len: i32 = state.hdr_len;
        //const paramAddr: WasiPtr = state.paramAddr;
        //const paramLen: i32 = state.paramLen;
        const bod_enable: i32 = state.bod_enable;
        const bod_ptr: WasiPtr = state.bod_ptr;
        const bod_len: i32 = state.bod_len;

        cu = try wasi.xdata.dupeZ(ally, uri_ptr, uri_len);

        //var cb: [:0]const u8 = "";
        if (bod_enable == 1) {
            cb = try wasi.xdata.dupeZ(ally, bod_ptr, bod_len);
        }

        en = @intToEnum(meth.Verb, verb);

        var list = try wasi.xslice(ally, hdr_ptr, hdr_len);
        defer ally.free(list);
        try rcvHeaders(ally, list);

        //var _params = wasi.xlist(ally, paramAddr, paramLen)
    }
    fn deinit() void {
        h.deinit();
    }
    fn rcvHeaders(ally: Allocator, list: []std.http.Field) !void {
        h = std.http.Headers.init(ally);
        var i: u32 = 0;
        while (i < list.len) : (i += 1) {
            const ent = list[i];
            try h.append(ent.name, ent.value);
            ally.free(ent.name);
            ally.free(ent.value);
        }
    }
};

// C/interop address
const WasiPtr = i32;
