const std = @import("std");
const wasi = @import("wasi.zig");
const meth = @import("../web/method.zig");
const Allocator = std.mem.Allocator;

// request.method
pub fn method() std.http.Method {
    return context.verb;
}
// request.body
pub fn body() [:0]const u8 {
    ////return context.get("body").?;
    return context.cbod;
}
// request.uri
pub fn uri() [:0]const u8 {
    ////return context.get("uri").?;
    return context.curi;
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
    var al: Allocator = undefined;
    var h: std.http.Headers = undefined;
    var verb: std.http.Method = undefined;
    var curi: [:0]const u8 = undefined;
    var cbod: [:0]const u8 = undefined;

    // accept mem addresses from C/interop
    fn init(ally: Allocator, state: anytype) !void {
        const rcv_method: i32 = state.method;
        const uri_ptr: i32 = state.uri_ptr;
        const uri_len: i32 = state.uri_len;
        const hdr_ptr: i32 = state.hdr_ptr;
        const hdr_len: i32 = state.hdr_len;
        //const paramAddr: WasiPtr = state.paramAddr;
        //const paramLen: i32 = state.paramLen;
        const bod_enable: i32 = state.bod_enable;
        const bod_ptr: i32 = state.bod_ptr;
        const bod_len: i32 = state.bod_len;
        al = ally;
        verb = meth.rcvMethod(rcv_method);
        curi = try wasi.xdata.dupeZ(ally, uri_ptr, uri_len);

        //var cbod: [:0]const u8 = "";
        if (bod_enable == 1) {
            cbod = try wasi.xdata.dupeZ(ally, bod_ptr, bod_len);
        }

        var list = try wasi.xslice(ally, hdr_ptr, hdr_len);
        defer ally.free(list);
        try rcvHeaders(ally, list);

        //var _params = wasi.xlist(ally, paramAddr, paramLen)
    }
    fn deinit() void {
        al.free(curi);
        al.free(cbod);
        h.deinit();
    }
    // std.http.Headers make copies of the fields
    fn rcvHeaders(ally: Allocator, list: []std.http.Field) !void {
        h = std.http.Headers.init(ally);
        var i: u32 = 0;
        while (i < list.len) : (i += 1) {
            const ent = list[i];
            try h.append(ent.name, ent.value);
            // owned fields have been copied into headers
            ally.free(ent.name);
            ally.free(ent.value);
        }
    }
};

// C/interop address
//const WasiPtr = i32;
