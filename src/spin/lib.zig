const std = @import("std");
const Allocator = std.mem.Allocator;
// static allocator
var gpal = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpal.allocator();

// signature for scripters to write custom handlers (in zig)
pub const EvalFn = *const fn (ally: Allocator, w: *HttpResponse, r: anytype) void;
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
    arg_uri_ptr: WasiAddr,
    arg_uri_len: i32,
    arg_hdr_ptr: WasiAddr,
    arg_hdr_len: i32,
    arg_par_ptr: WasiAddr,
    arg_par_len: i32,
    arg_body: i32,
    arg_bod_ptr: WasiAddr,
    arg_bod_len: i32,
) callconv(.C) WasiAddr {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const ally = arena.allocator();
    // life cycle begins
    preprocess(ally, .{
        .method = arg_method,
        .uri_ptr = arg_uri_ptr,
        .uri_len = arg_uri_len,
        .hdr_ptr = arg_hdr_ptr,
        .hdr_len = arg_hdr_len,
        .par_ptr = arg_par_ptr,
        .par_len = arg_par_len,
        .bod_enable = arg_body,
        .bod_ptr = arg_bod_ptr,
        .bod_len = arg_bod_len,
    }) catch @panic("out of mem at start of cycle");
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
            scripts(ally, &response, .{
                .method = http.method(),
                .uri = http.uri(),
                .body = http.body(),
                .headers = http.headers(),
            });
        }
    };
    break :blk keeper;
};

// static request in life cycle
//var request: Request = undefined;
var response: HttpResponse = undefined;
// life cycle pre-process step
fn preprocess(ally: Allocator, state: anytype) !void {
    // map memory addresses received from C/host
    try http.init(ally, state);

    // new response writer in life cycle
    response = HttpResponse.init(ally);
}
// "null" script (zero case template)
fn vanilla(ally: Allocator, w: *HttpResponse, r: anytype) void {
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
pub const http = @import("http.zig");

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

    pub fn deinit(self: *Self) void {
        //TODO free map items
        self.headers.deinit();
        self.body.deinit();
    }
};

// C/interop address
pub const WasiAddr = i32;
// "anon" struct just for address to tuple C/interop
const WasiStr = extern struct { ptr: [*c]u8, len: usize };
const WasiTuple = extern struct { f0: WasiStr, f1: WasiStr };

/// HTTP status codes.
pub const HttpStatus = u16;
