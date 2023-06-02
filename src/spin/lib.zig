const std = @import("std");
const Allocator = std.mem.Allocator;
// static allocator
var gpal = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpal.allocator();

// signature for scripters to write custom handlers (in zig)
pub const EvalFn = *const fn (ally: Allocator, w: *HttpResponse, r: *Request) void;
pub fn handle(comptime h: EvalFn) void {
    nested.next(h);
}

// begin exports required by C/host
comptime {
    @export(guestHttpInit, .{ .name = "handle-http-request" });
    @export(canAbiRealloc, .{ .name = "canonical_abi_realloc" });
    @export(canAbiFree, .{ .name = "canonical_abi_free" });
}
var RET_AREA: [28]u8 align(4) = std.mem.zeroes([28]u8);
// entry point for C/host to guest process env
fn guestHttpInit(
    arg_method: i32,
    arg_uriAddr: WasiAddr,
    arg_uriLen: i32,
    arg_hdrAddr: WasiAddr,
    arg_hdrLen: i32,
    arg_paramAddr: WasiAddr,
    arg_paramLen: i32,
    arg_body: i32,
    arg_bodyAddr: WasiAddr,
    arg_bodyLen: i32,
) callconv(.C) WasiAddr {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const ally = arena.allocator();
    // life cycle begins
    preprocess(
        ally,
        arg_method,
        arg_uriAddr,
        arg_uriLen,
        arg_hdrAddr,
        arg_hdrLen,
        arg_paramAddr,
        arg_paramLen,
        arg_body,
        arg_bodyAddr,
        arg_bodyLen,
    );
    nested.eval(ally);

    // address of memory shared to the C/host
    var re: WasiAddr = @intCast(WasiAddr, @ptrToInt(&RET_AREA));
    // copy HTTP status code into the shared mem
    @intToPtr([*c]i16, @intCast(usize, re)).* = @intCast(i16, response.status);
    // copy headers to shared mem
    if (response.headers.count() != 0) {
        var ar = response.headers_as_array(ally).items;
        @intToPtr([*c]i8, @intCast(usize, re + 4)).* = 1;
        @intToPtr([*c]i32, @intCast(usize, re + 12)).* = @intCast(i32, ar.len);
        @intToPtr([*c]i32, @intCast(usize, re + 8)).* = @intCast(i32, @ptrToInt(ar.ptr));
    } else {
        @intToPtr([*c]i8, @intCast(usize, re + 4)).* = 0;
    }
    // copy body to shared mem
    if (response.body.items.len != 0) {
        var cp = ally.dupe(u8, response.body.items) catch {
            @panic("FAIL response OutOfMem");
        };
        @intToPtr([*c]i8, @intCast(usize, re + 16)).* = 1;
        @intToPtr([*c]i32, @intCast(usize, re + 24)).* = @intCast(i32, cp.len);
        @intToPtr([*c]i32, @intCast(usize, re + 20)).* = @intCast(i32, @ptrToInt(cp.ptr));
    } else {
        @intToPtr([*c]i8, @intCast(usize, re + 16)).* = 0;
    }

    return re;
}

fn canAbiRealloc(
    arg_ptr: ?[*]u8,
    arg_oldsz: usize,
    arg_align: usize,
    arg_newsz: usize,
) callconv(.C) ?[*]u8 {
    // zero means to _free_ in ziglang
    // TODO (need to confirm behavior from wit-bindgen version)
    if (arg_newsz == 0) {
        return @intToPtr(?[*]u8, arg_align);
    }

    // null means to _allocate_
    if (arg_ptr == null) {
        const newslice = gpa.alloc(u8, arg_newsz) catch return null;
        return newslice.ptr;
    }

    var slice = (arg_ptr.?)[0..arg_oldsz];
    const reslice = gpa.realloc(slice, arg_newsz) catch return null;
    return reslice.ptr;
}

fn canAbiFree(arg_ptr: ?[*]u8, arg_size: usize, arg_align: usize) callconv(.C) void {
    _ = arg_align;
    if (arg_size == 0) return;
    if (arg_ptr == null) return;

    gpa.free((arg_ptr.?)[0..arg_size]);
}
// end exports to comply with host

// namespace nesting (private in our case)
const nested = blk: {
    // static event handlers
    var scripts: EvalFn = vanilla;

    const keeper = struct {
        // wire-up user defined script to be run
        fn next(comptime h: EvalFn) void {
            scripts = h;
        }
        // life cycle step
        fn eval(ally: Allocator) void {
            scripts(ally, &response, &request);
        }
    };
    break :blk keeper;
};

// static request in life cycle
var request: Request = undefined;
var response: HttpResponse = undefined;
// life cycle pre-process step
fn preprocess(
    ally: Allocator,
    arg_method: i32,
    arg_uriAddr: WasiAddr,
    arg_uriLen: i32,
    arg_hdrAddr: WasiAddr,
    arg_hdrLen: i32,
    arg_paramAddr: WasiAddr,
    arg_paramLen: i32,
    arg_body: i32,
    arg_bodyAddr: WasiAddr,
    arg_bodyLen: i32,
) void {
    // ingest memory locations received from C/host
    request = Request.init(
        ally,
        arg_method,
        arg_uriAddr,
        arg_uriLen,
        arg_hdrAddr,
        arg_hdrLen,
        arg_paramAddr,
        arg_paramLen,
        arg_body,
        arg_bodyAddr,
        arg_bodyLen,
    );
    // new response writer in life cycle
    response = HttpResponse.init(ally);
}
// "null" script (zero case template)
fn vanilla(ally: Allocator, w: *HttpResponse, r: *Request) void {
    _ = r;
    _ = ally;
    w.body.appendSlice("vanilla placeholder") catch {
        w.status = 500;
        return;
    };
    w.status = 200;
}

// expose namespaces for convenience
pub const redis = @import("redis.zig");
pub const config = @import("config.zig");
pub const outbound = @import("outbound.zig");
pub const wasi = @import("wasi.zig");
const phi = @import("../web/phi.zig");

// The basic type according to translate-c
// ([*c]u8 is both char* and uint8*)
const xdata = struct {
    const Self = @This();
    ptr: [*c]u8,
    len: usize,

    // cast address to pointer w/o allocation
    pub fn init(addr: WasiAddr, len: i32) Self {
        return Self{
            .ptr = @intToPtr([*c]u8, @intCast(usize, addr)),
            .len = @intCast(usize, len),
        };
    }
    // convert as slice w/ new memory (todo provide different return types explicitly i.e., dupeZ for the sentinel)
    pub fn dupe(self: Self, ally: Allocator) []u8 {
        const old = self.ptr[0..self.len];
        var cp = ally.dupe(u8, old) catch {
            @panic("FAIL xdata dupe ");
        };
        return cp;
    }
    // release memory that was allocated by CanonicalAbiAlloc
    pub fn deinit(self: *Self) void {
        canAbiFree(self.ptr, self.len, 1);
        self.len = 0;
        self.ptr = null;
    }
};

// writer for ziglang consumer
pub const HttpResponse = struct {
    const Self = @This();
    status: HttpStatus,
    headers: std.StringHashMap([]const u8),
    body: std.ArrayList(u8),

    pub fn init(ally: Allocator) Self {
        return Self{
            .status = @enumToInt(std.http.Status.not_found),
            .headers = std.StringHashMap([]const u8).init(ally),
            .body = std.ArrayList(u8).init(ally),
        };
    }
    // conversion for C/interop
    pub fn headers_as_array(self: Self, ally: Allocator) std.ArrayList(WasiTuple) {
        var arr = std.ArrayList(WasiTuple).init(ally);
        var iter = self.headers.iterator();
        while (iter.next()) |entry| {
            var key = ally.dupe(u8, entry.key_ptr.*) catch {
                @panic("FAIL headers key dupe");
            };
            var val = ally.dupe(u8, entry.value_ptr.*) catch {
                @panic("FAIL headers val dupe");
            };
            var tup = WasiTuple{
                .f0 = WasiStr{ .ptr = key.ptr, .len = key.len },
                .f1 = WasiStr{ .ptr = val.ptr, .len = val.len },
            };
            arr.append(tup) catch {
                @panic("FAIL headers slice");
            };
        }
        return arr;
    }
    // TODO should ownership be taken from arena when transfering to host domain
    pub fn deinit(self: *Self) void {
        //TODO free map items
        self.headers.deinit();
        self.body.deinit();
    }
};

// reader for ziglang consumer
pub const Request = struct {
    const Self = @This();
    ally: Allocator,
    method: HttpMethod,
    uri: []const u8,
    headers: phi.RawHeaders,
    params: phi.RawHeaders,
    body: *std.io.FixedBufferStream([]u8),

    // instantiate from C/interop (using addresses)
    pub fn init(
        ally: Allocator,
        method: i32,
        uriAddr: WasiAddr,
        uriLen: i32,
        hdrAddr: WasiAddr,
        hdrLen: i32,
        paramAddr: WasiAddr,
        paramLen: i32,
        bodyEnable: i32,
        bodyAddr: WasiAddr,
        bodyLen: i32,
    ) Self {
        // TODO is this copy clean?
        var curi = xdata.init(uriAddr, uriLen);
        var req_uri = curi.dupe(ally);
        curi.deinit();

        var content_body: std.io.FixedBufferStream([]u8) = undefined;
        if (bodyEnable == 1) {
            var cbod = xdata.init(bodyAddr, bodyLen);
            content_body = std.io.fixedBufferStream(cbod.ptr[0..cbod.len]);
        }

        var req_headers = wasi.xlist(ally, hdrAddr, hdrLen) catch {
            @panic("FAIL copying headers from C addr");
        };
        var qry_params = wasi.xlist(ally, paramAddr, paramLen) catch {
            @panic("FAIL copying params from C addr");
        };

        return Self{
            .ally = ally,
            .method = @intCast(HttpMethod, method),
            .uri = req_uri,
            .headers = req_headers,
            .params = qry_params,
            .body = &content_body,
        };
    }
    // TODO relying on arena to free at the end
    //pub fn deinit(self: *Self) void {
    // TODO bus error (maybe refactor to non-allocating for now)
    //}
};

// C/interop address
pub const WasiAddr = i32;
// "anon" struct just for address to tuple C/interop
const WasiStr = extern struct { ptr: [*c]u8, len: usize };
const WasiTuple = extern struct { f0: WasiStr, f1: WasiStr };

/// HTTP status codes.
pub const HttpStatus = u16;
/// HTTP method verb.
pub const HttpMethod = u8;
