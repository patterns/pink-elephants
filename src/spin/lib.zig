const std = @import("std");
const wasi = @import("wasi.zig");
const http = @import("http.zig");
const status = @import("../web/status.zig");
const Allocator = std.mem.Allocator;
// static allocator
var gpal = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpal.allocator();

// signature for scripters to write custom handlers (in zig)
pub const EvalFn = *const fn (ally: Allocator, ret: anytype, rcv: anytype) void;
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
    arg_uri_ptr: i32,
    arg_uri_len: i32,
    arg_hdr_ptr: i32,
    arg_hdr_len: i32,
    arg_par_ptr: i32,
    arg_par_len: i32,
    arg_body: i32,
    arg_bod_ptr: i32,
    arg_bod_len: i32,
) callconv(.C) i32 {
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
    }) catch @panic("Mem preproc fault");

    nested.eval(ally);

    return postprocess();
}
fn canAbiRealloc(
    arg_ptr: ?*anyopaque,
    arg_oldsz: usize,
    arg_align: usize,
    arg_newsz: usize,
) callconv(.C) ?*anyopaque {
    if (arg_newsz == 0) {
        const newslice = gpa.alloc(u8, arg_align) catch @panic("Size 0 realloc fault");
        return newslice.ptr;
    }
    if (arg_ptr == null) {
        const newslice = gpa.alloc(u8, arg_newsz) catch @panic("Null ptr realloc fault");
        return newslice.ptr;
    }

    var cp = @ptrCast([*]u8, arg_ptr.?);
    var slice = cp[0..arg_oldsz];
    const reslice = gpa.realloc(slice, arg_newsz) catch @panic("Resize realloc fault");
    return reslice.ptr;
}
fn canAbiFree(arg_ptr: ?*anyopaque, arg_size: usize, arg_align: usize) callconv(.C) void {
    // so based on above, does size zero mean to use align as size?
    if (arg_size == 0) @panic("Zero free fault");
    if (arg_ptr == null) @panic("Null ptr free fault");
    _ = arg_align;
    //std.debug.assert(arg_align == @alignOf(usize));
    var cp = @ptrCast([*]u8, arg_ptr.?);
    var slice = cp[0..arg_size];
    gpa.free(slice);
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
            scripts(ally, .{
                .headers = wasi.headers(),
                .body = wasi.body(),
            }, .{
                .method = http.method(),
                .uri = http.uri(),
                .body = http.body(),
                .headers = http.headers(),
            });
        }
    };
    break :blk keeper;
};

// life cycle pre-process step
fn preprocess(ally: Allocator, state: anytype) !void {
    // map memory addresses received from C/host
    try http.init(ally, state);
    // initialize response writer in life cycle
    wasi.shipping(ally);
}
// "null" script (zero case template)
fn vanilla(ally: Allocator, ret: anytype, rcv: anytype) void {
    _ = rcv;
    _ = ally;
    ret.body.appendSlice("vanilla placeholder") catch {
        status.internal();
        return;
    };
    status.ok();
}
// life cycle post-process step
fn postprocess() i32 {
    const ally = wasi.shipAllocator();
    const ret = wasi.shipReturns();

    // TODO most of this feels very wasi, does it need to move into wasi namespace?

    // address of memory shared to the C/host
    const ad: i32 = @intCast(i32, @ptrToInt(&RET_AREA));
    // copy HTTP status code to share
    @intToPtr([*c]i16, @intCast(usize, ad)).* = @as(i16, @enumToInt(ret.status));

    // store headers to share
    if (ret.headers.list.items.len != 0) {
        const ar = wasi.shipFields(ally, ret.headers) catch @panic("Own fields fault");
        @intToPtr([*c]i8, @intCast(usize, ad + 4)).* = 1;
        @intToPtr([*c]i32, @intCast(usize, ad + 12)).* = @intCast(i32, ar.len);
        @intToPtr([*c]i32, @intCast(usize, ad + 8)).* = @intCast(i32, @ptrToInt(ar.ptr));
    } else {
        @intToPtr([*c]i8, @intCast(usize, ad + 4)).* = 0;
    }

    // store content to share
    if (ret.body.items.len != 0) {
        const cp = ret.body.items;
        @intToPtr([*c]i8, @intCast(usize, ad + 16)).* = 1;
        @intToPtr([*c]i32, @intCast(usize, ad + 24)).* = @intCast(i32, cp.len);
        @intToPtr([*c]i32, @intCast(usize, ad + 20)).* = @intCast(i32, @ptrToInt(cp.ptr));
    } else {
        @intToPtr([*c]i8, @intCast(usize, ad + 16)).* = 0;
    }

    // address to share
    return ad;
}

// act as umbrella namespace for the sdk
pub const redis = @import("redis.zig");
pub const config = @import("config.zig");
pub const outbound = @import("outbound.zig");
