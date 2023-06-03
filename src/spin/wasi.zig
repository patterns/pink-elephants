const std = @import("std");
const Allocator = std.mem.Allocator;
// static allocator
var gpal = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpal.allocator();

// TODO lots to refactor as we want to leverage for use in outbound
//      (and consolidate out from lib)
// raw-headers can probably be replaced by std.http.Headers
const phi = @import("../web/phi.zig");

// convert std.http.Headers to array
//pub fn toTuples(ally: Allocator, h: std.http.Headers) !std.ArrayList(Xtup) {
// purpose, because to pass the headers to the host we need to be in
// the interop format of records in contiguous memory.

// todo which namespace is the proper home? (outbound?)

//    var arr = std.ArrayList(Xtup).init(ally);
//    var it = h.index.iterator();
//    while (it.next()) |entry| {

//var key = try ally.dupe(u8, entry.key_ptr.*);
//var val = try ally.dupe(u8, entry.val_ptr.*);
//try arr.append( Xtup{
//        .f0 = Xstr{ .ptr = key.ptr, .len = key.len },
//        .f1 = Xstr{ .ptr = val.ptr, .len = val.len },
//});
//    }
//    return arr;
//}
// convert raw headers which are C array into array-list
pub fn headers_as_array(ally: Allocator, headers: phi.RawHeaders) std.ArrayList(Xtup) {
    var arr = std.ArrayList(Xtup).init(ally);
    var iter = headers.iterator();
    while (iter.next()) |entry| {
        var key = ally.dupe(u8, entry.key_ptr.*) catch {
            @panic("FAIL headers key dupe");
        };
        var val = ally.dupe(u8, entry.value_ptr.*) catch {
            @panic("FAIL headers val dupe");
        };
        var tup = Xtup{
            .f0 = Xstr{ .ptr = key.ptr, .len = key.len },
            .f1 = Xstr{ .ptr = val.ptr, .len = val.len },
        };
        arr.append(tup) catch {
            @panic("FAIL headers slice");
        };
    }
    return arr;
}

// C/interop address
const Xaddr = i32;
// "anon" struct just for address to tuple C/interop
pub const Xstr = extern struct { ptr: [*c]u8, len: usize };
pub const Xtup = extern struct { f0: Xstr, f1: Xstr };

// HTTP status codes.
const HttpStatus = u16;
// HTTP method verb.
const HttpMethod = u8;

// The basic type according to translate-c
// ([*c]u8 is both char* and uint8*)
pub const xdata = struct {
    const Self = @This();
    ptr: [*c]u8,
    len: usize,

    // cast address to pointer w/o allocation
    pub fn init(addr: Xaddr, len: i32) Self {
        return Self{
            .ptr = @intToPtr([*c]u8, @intCast(usize, addr)),
            .len = @intCast(usize, len),
        };
    }
    // shortcut for cloning C string
    pub fn dupeZ(ally: Allocator, addr: Xaddr, len: i32) ![:0]u8 {
        const ptr = @intToPtr([*c]u8, @intCast(usize, addr));
        const sz = @intCast(usize, len);
        const old = ptr[0..sz];
        return ally.dupeZ(u8, old);
    }

    // convert as slice w/ new memory (todo provide different return types explicitly i.e., dupeZ for the sentinel)
    pub fn dupe(self: Self, ally: Allocator) []u8 {
        const old = self.ptr[0..self.len];
        var cp = ally.dupe(u8, old) catch {
            @panic("FAIL xdata dupe ");
        };
        return cp;
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
    gpa.free(ptr.?[0..len]);
}

// list conversion from C arrays
//(todo ?will replace raw-headers with std.http.Headers)
pub fn xlist(ally: Allocator, addr: Xaddr, rowcount: i32) !phi.RawHeaders {
    var record = @intToPtr([*c]Xtup, @intCast(usize, addr));
    const max = @intCast(usize, rowcount);
    var list: phi.RawHeaders = undefined;

    var rownum: usize = 0;
    while (rownum < max) : (rownum += 1) {
        var tup = record[rownum];

        list[rownum] = phi.RawField{
            .fld = try std.fmt.allocPrint(ally, "{s}", .{tup.f0.ptr[0..tup.f0.len]}),
            .val = try std.fmt.allocPrint(ally, "{s}", .{tup.f1.ptr[0..tup.f1.len]}),
        };
    }
    return list;
}

// C array to header set
pub fn xmap(ally: Allocator, ad: Xaddr, rowcount: i32) !std.http.Headers {
    const record = @intToPtr([*c]Xtup, @intCast(usize, ad));
    const max = @intCast(usize, rowcount);

    var map = std.http.Headers.init(ally);
    var rownum: usize = 0;
    while (rownum < max) : (rownum += 1) {
        const tup = record[rownum];
        const fld = tup.f0.ptr[0..tup.f0.len];
        const val = tup.f1.ptr[0..tup.f1.len];
        try map.append(fld, val);
    }
    return map;
}
