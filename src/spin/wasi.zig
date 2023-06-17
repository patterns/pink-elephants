const std = @import("std");
const Allocator = std.mem.Allocator;

// prepare ownership switch to control by C/host
pub fn shipFields(ally: Allocator, h: std.http.Headers) ![]Xfield {
    var fld_list = std.ArrayList(Xfield).init(ally);
    for (h.list.items) |entry| {
        if (entry.value.len == 0) continue;

        const fld = try ally.dupeZ(u8, entry.name);
        const val = try ally.dupeZ(u8, entry.value);
        try fld_list.append(.{
            .f0 = .{ .ptr = fld.ptr, .len = fld.len },
            .f1 = .{ .ptr = val.ptr, .len = val.len },
        });
    }
    return fld_list.toOwnedSlice();
}

// C/interop (direction ship from guest to host)
pub const Xcstr = extern struct { ptr: [*:0]u8, len: usize };
pub const Xfield = extern struct { f0: Xcstr, f1: Xcstr };

// C/interop (direction of from host to guest)
const Xptr = i32;
// "anon" struct just for address to tuple C/interop
const Xstr = extern struct { ptr: [*c]const u8, len: usize };
const Xtup = extern struct { f0: Xstr, f1: Xstr };

// C array to slice
pub fn xslice(ally: Allocator, ad: Xptr, rowcount: i32) ![]std.http.Field {
    const record = @intToPtr([*c]Xtup, @intCast(usize, ad));
    const max = @intCast(usize, rowcount);

    var pairs = std.ArrayList(std.http.Field).init(ally);
    var rownum: usize = 0;
    while (rownum < max) : (rownum +%= 1) {
        const tup = record[rownum];
        const fld = tup.f0.ptr[0..tup.f0.len];
        const val = tup.f1.ptr[0..tup.f1.len];
        try pairs.append(.{
            .name = try ally.dupeZ(u8, fld),
            .value = try ally.dupeZ(u8, val),
        });
    }
    return pairs.toOwnedSlice();
}

// allocator for caller to prep returns for shipping (back to C/host)
pub fn shipAllocator() Allocator {
    return returns.fba.allocator();
}
// accumulated fields which caller will use to prep returns step
pub fn shipReturns() struct {
    status: std.http.Status,
    headers: std.http.Headers,
    body: std.ArrayList(u8),
} {
    return .{
        .status = returns.status,
        .headers = returns.h,
        .body = returns.json,
    };
}

pub fn headers() *std.http.Headers {
    return &returns.h;
}
pub fn body() *std.ArrayList(u8) {
    return &returns.json;
}
// not used directed and wrapped by web/status for convenience
pub fn status(s: std.http.Status) void {
    returns.status = s;
}

// *init* for the returns overlay
pub fn shipping(ally: Allocator) void {
    returns.fba = std.heap.FixedBufferAllocator.init(&SHIP_RETURNS);
    returns.status = std.http.Status.service_unavailable;
    returns.h = std.http.Headers.init(ally);
    returns.json = std.ArrayList(u8).init(ally);
}
// static global to back the shipping allocations (outside arena.deinit scope)
var SHIP_RETURNS: [8192]u8 align(4) = std.mem.zeroes([8192]u8);
// namespace nesting (to overlay return items of "response")
const returns = struct {
    // static vars
    var fba: std.heap.FixedBufferAllocator = undefined;
    var status: std.http.Status = undefined;
    var h: std.http.Headers = undefined;
    var json: std.ArrayList(u8) = undefined;
};

//todo clean up, not used very much.....
// The basic type according to translate-c
// ([*c]u8 is both char* and uint8*)
pub const xdata = struct {
    const Self = @This();
    ptr: [*c]u8,
    len: usize,

    // cast address to pointer w/o allocation
    pub fn init(addr: Xptr, len: i32) Self {
        return Self{
            .ptr = @intToPtr([*c]u8, @intCast(usize, addr)),
            .len = @intCast(usize, len),
        };
    }
    // shortcut for cloning C string
    pub fn dupeZ(ally: Allocator, addr: Xptr, len: i32) ![:0]u8 {
        const ptr = @intToPtr([*c]u8, @intCast(usize, addr));
        const sz = @intCast(usize, len);
        const old = ptr[0..sz];
        return ally.dupeZ(u8, old);
    }

    // convert as slice w/ new memory (todo provide different return types explicitly i.e., dupeZ for the sentinel)
    pub fn dupe(self: Self, ally: Allocator) ![:0]u8 {
        const old = self.ptr[0..self.len];
        return ally.dupeZ(u8, old);
    }
    // release memory that was allocated by host (using CanonicalAbiAlloc)
    pub fn deinit(self: *Self) void {
        gpfree(self.ptr, self.len);
        self.len = 0;
        self.ptr = null;
    }
};

// release memory that was allocated by host (using CanonicalAbiAlloc)
fn gpfree(ptr: ?[*]u8, len: usize) void {
    if (len == 0 or ptr == null) return;
    var gpal = std.heap.GeneralPurposeAllocator(.{}){};
    gpal.allocator().free(ptr.?[0..len]);
}
