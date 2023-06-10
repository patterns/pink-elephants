const std = @import("std");

const wasi = @import("wasi.zig");
const Allocator = std.mem.Allocator;

// request.method
pub fn method() Verb {
    //const eq = std.ascii.eqlIgnoreCase;
    const cm = context.get("method").?;

    const en = Verb.fromDescr(cm);
    return en;
    //if (eq("get", cm)) return 0;
    //if (eq("post", cm)) return 1;
    //std.debug.assert(unreachable);
}
// request.body
pub fn body() [:0]const u8 {
    return context.get("body").?;
}
// request.uri
pub fn uri() [:0]const u8 {
    return context.get("uri").?;
}
// request.headers
pub fn headers() std.http.Headers {
    return context.h();
}

//TODO auth params (leaf nodes of signature header)

// the request received
pub fn init(ally: Allocator, state: anytype) !void {
    try context.init(ally, state);
}
pub fn deinit() void {
    context.deinit();
}

// namespace nesting (to overlay request fields)
const context = struct {
    // static variables
    var raw: std.BoundedArray(std.http.Field, 128) = undefined;
    var map: std.StringHashMap([:0]const u8) = undefined;
    var hx2: std.http.Headers = undefined;

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

        map = std.StringHashMap([:0]const u8).init(ally);
        const cu = try wasi.xdata.dupeZ(ally, uri_ptr, uri_len);
        try map.put("uri", cu);

        var cb: [:0]const u8 = "";
        if (bod_enable == 1) {
            cb = try wasi.xdata.dupeZ(ally, bod_ptr, bod_len);
        }
        try map.put("body", cb);

        const en = @intToEnum(Verb, verb);
        try map.put("method", en.toDescr());

        raw = try std.BoundedArray(std.http.Field, 128).fromSlice(try wasi.xslice(ally, hdr_ptr, hdr_len));
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
            var i: u32 = 0;
            while (i < raw.len) : (i += 1) {
                const ent = raw.get(i);
                hx2.append(ent.name, ent.value) catch {
                    std.log.err("headers append fault", .{});
                    break;
                };
            }
        }
        return hx2;
    }
    // general way to access 80% fields (minimal interface of request)
    fn get(comptime name: []const u8) ?[:0]const u8 {
        return map.get(name);
    }
};

// C/interop address
const WasiPtr = i32;
// "anon" struct just for address to tuple C/interop
const WasiStr = extern struct { ptr: [*c]u8, len: usize };
const WasiTuple = extern struct { f0: WasiStr, f1: WasiStr };

// http method / verbs (TODO don't expose publicly if possible)
pub const Verb = enum(u8) {
    get = 0,
    post = 1,
    put = 2,
    delete = 3,
    patch = 4,
    head = 5,
    options = 6,

    // description (name) format of the enum
    pub fn toDescr(self: Verb) [:0]const u8 {
        //return DescrTable[@enumToInt(self)];
        // insted of table, switch
        switch (self) {
            .get => return "get",
            .post => return "post",
            .put => return "put",
            .delete => return "delete",
            .patch => return "patch",
            .head => return "head",
            .options => return "options",
        }
    }

    // convert to enum
    pub fn fromDescr(text: []const u8) Verb {
        const eq = std.ascii.eqlIgnoreCase;
        for (DescrTable, 0..) |row, rownum| {
            if (eq(row, text)) {
                return @intToEnum(Verb, rownum);
            }
        }
        unreachable;
    }
    // TODO remove the table in favor of switch
    // lookup table with the description
    pub const DescrTable = [@typeInfo(Verb).Enum.fields.len][:0]const u8{
        "get",
        "post",
        "put",
        "delete",
        "patch",
        "head",
        "options",
    };
};
