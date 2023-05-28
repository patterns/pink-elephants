const std = @import("std");
const Allocator = std.mem.Allocator;

// convert std.http.Headers to array of tuples
pub fn toTuples(ally: Allocator, h: std.http.Headers) std.ArrayList(WasiTuple) {
    // todo which namespace is the proper home? (outbound?)
    // consider: we need this to go from std.http.Headers to the wasi tuple, worth it?

}

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

// list conversion from C arrays
fn xlist(addr: WasiAddr, rowcount: i32) !phi.RawHeaders {
    var record = @intToPtr([*c]WasiTuple, @intCast(usize, addr));
    const max = @intCast(usize, rowcount);
    var list: phi.RawHeaders = undefined;

    var rownum: usize = 0;
    while (rownum < max) : (rownum +%= 1) {
        var tup = record[rownum];

        // some arbitrary limits on field lengths (until we achieve sig header)
        std.debug.assert(tup.f0.len < 128);
        std.debug.assert(tup.f1.len < 512);
        var fld: [128]u8 = undefined;
        var val: [512]u8 = undefined;
        _ = try std.fmt.bufPrintZ(&fld, "{s}", .{tup.f0.ptr[0..tup.f0.len]});
        _ = try std.fmt.bufPrintZ(&val, "{s}", .{tup.f1.ptr[0..tup.f1.len]});

        list[rownum] = phi.RawField{ .fld = &fld, .val = &val };

        // free old kv
        canAbiFree(@ptrCast(?[*]u8, tup.f0.ptr), tup.f0.len, 1);
        canAbiFree(@ptrCast(?[*]u8, tup.f1.ptr), tup.f1.len, 1);
    }
    // free the old array
    canAbiFree(@ptrCast(?[*]u8, record), max *% 16, 4);
    return list;
}

// map conversion from C arrays (leaning on xlist as primary to strive for minimal)
fn xmap(al: Allocator, addr: WasiAddr, len: i32) std.StringHashMap([]const u8) {
    var record = @intToPtr([*c]WasiTuple, @intCast(usize, addr));
    const count = @intCast(usize, len);

    var map = std.StringHashMap([]const u8).init(al);
    var i: usize = 0;
    while (i < count) : (i +%= 1) {
        var kv = record[i];

        var key = al.dupe(u8, kv.f0.ptr[0..kv.f0.len]) catch {
            @panic("FAIL map key dupe ");
        };
        var val = al.dupe(u8, kv.f1.ptr[0..kv.f1.len]) catch {
            @panic("FAIL map val dupe ");
        };

        map.put(key, val) catch {
            @panic("FAIL map put, ");
        };
        // free old kv
        canAbiFree(@ptrCast(?[*]u8, kv.f0.ptr), kv.f0.len, 1);
        canAbiFree(@ptrCast(?[*]u8, kv.f1.ptr), kv.f1.len, 1);
    }
    // free the old array
    canAbiFree(@ptrCast(?[*]u8, record), count *% 16, 4);
    return map;
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

// C/interop address
const WasiAddr = i32;
// "anon" struct just for address to tuple C/interop
const WasiStr = extern struct { ptr: [*c]u8, len: usize };
const WasiTuple = extern struct { f0: WasiStr, f1: WasiStr };

// HTTP status codes.
const HttpStatus = u16;
// HTTP method verb.
const HttpMethod = u8;
