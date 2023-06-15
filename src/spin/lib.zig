const std = @import("std");
const wasi = @import("wasi.zig");
const Allocator = std.mem.Allocator;
// static allocator
var gpal = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpal.allocator();

// signature for scripters to write custom handlers (in zig)
pub const EvalFn = *const fn (ally: Allocator, w: *HttpResponse, rcv: anytype) void;
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
    ////defer arena.deinit();
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

    return postprocess(ally);
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
            scripts(ally, &writer, .{
                .method = http.method(),
                .uri = http.uri(),
                .body = http.body(),
                .headers = http.headers(),
            });
        }
    };
    break :blk keeper;
};

// static vars in life cycle
var writer: HttpResponse = undefined;
// life cycle pre-process step
fn preprocess(ally: Allocator, state: anytype) !void {
    // map memory addresses received from C/host
    try http.init(ally, state);
    // new response writer in life cycle
    writer = HttpResponse.init(ally);
}
// "null" script (zero case template)
fn vanilla(ally: Allocator, w: *HttpResponse, rcv: anytype) void {
    _ = rcv;
    _ = ally;
    w.body.appendSlice("vanilla placeholder") catch {
        w.status = std.http.Status.internal_server_error;
        return;
    };
    w.status = std.http.Status.ok;
}
// life cycle post-process step
fn postprocess(ally: Allocator) i32 {
    // address of memory shared to the C/host
    var re: i32 = @intCast(i32, @ptrToInt(&RET_AREA));
    // copy HTTP status code to share
    @intToPtr([*c]i16, @intCast(usize, re)).* = @as(i16, @enumToInt(writer.status));

    // store headers to share
    if (writer.headers.list.items.len != 0) {
        const ar = wasi.shipFields(ally, writer.headers) catch @panic("Own fields fault");
        writer.shipped_fields = ar;
        @intToPtr([*c]i8, @intCast(usize, re + 4)).* = 1;
        @intToPtr([*c]i32, @intCast(usize, re + 12)).* = @intCast(i32, ar.len);
        @intToPtr([*c]i32, @intCast(usize, re + 8)).* = @intCast(i32, @ptrToInt(ar.ptr));
    } else {
        @intToPtr([*c]i8, @intCast(usize, re + 4)).* = 0;
    }

    // store content to share
    if (writer.body.items.len != 0) {
        const cp = writer.body.toOwnedSlice() catch @panic("Own content fault");
        writer.shipped_content = cp;
        @intToPtr([*c]i8, @intCast(usize, re + 16)).* = 1;
        @intToPtr([*c]i32, @intCast(usize, re + 24)).* = @intCast(i32, cp.len);
        @intToPtr([*c]i32, @intCast(usize, re + 20)).* = @intCast(i32, @ptrToInt(cp.ptr));
    } else {
        @intToPtr([*c]i8, @intCast(usize, re + 16)).* = 0;
    }

    // address to share
    return re;
}

// act as umbrella namespace for the sdk
pub const redis = @import("redis.zig");
pub const config = @import("config.zig");
pub const outbound = @import("outbound.zig");
pub const http = @import("http.zig");

// REFACTORING the writer channel of the response destined for the browser user
pub const HttpResponse = struct {
    const Self = @This();
    status: std.http.Status,
    headers: std.http.Headers,
    body: std.ArrayList(u8),
    shipped_fields: []wasi.Xfield,
    shipped_content: []u8,

    pub fn init(ally: Allocator) Self {
        return Self{
            .status = std.http.Status.not_found,
            .headers = std.http.Headers.init(ally),
            .body = std.ArrayList(u8).init(ally),
            .shipped_fields = undefined,
            .shipped_content = undefined,
        };
    }
    pub fn deinit(self: *Self) void {
        self.headers.deinit();
        self.body.deinit();
    }
};
