const std = @import("std");
const config = @import("config.zig");
const log = std.log;

// add _job_ item that will be picked up by a _worker_
pub fn enqueue(ally: std.mem.Allocator, content: std.json.ValueTree) !void {
    var bucket = std.ArrayList(u8).init(ally);
    defer bucket.deinit();
    try content.root.jsonStringify(.{}, bucket.writer());

    // duplicate payload to sentinel-terminated
    const cpayload = try ally.dupeZ(u8, bucket.items);
    defer ally.free(cpayload);

    //TODO want the SHA checksum from the header for uniqueness
    var key: []const u8 = undefined;
    var idval = content.root.object.get("id");
    if (idval) |v| {
        key = v.string;
    } else {
        // fallback pseudo-id
        key = try std.fmt.allocPrintZ(ally, "{d}", .{std.time.milliTimestamp()});
    }
    // duplicate id to sentinel-terminated
    //const key = content.root.object.get("id").?.string;
    const ckey = try ally.dupeZ(u8, key);
    defer ally.free(ckey);

    // duplicate redis address to sentinel-terminated
    const addr: []const u8 = config.redisAddress() orelse "redis://127.0.0.1:6379";
    const caddr = try ally.dupeZ(u8, addr);
    defer ally.free(caddr);

    saveEvent(caddr, ckey, cpayload);
}

// capture extra request detail to debug/tests
pub fn debugDetail(ally: std.mem.Allocator, option: anytype) !void {
    const tree = option.tree;
    const rcv = option.rcv;

    var bucket = std.ArrayList(u8).init(ally);
    defer bucket.deinit();
    try tree.root.jsonStringify(.{}, bucket.writer());
    try bucket.appendSlice("##DEBUG##");
    try rcv.headers.format("{s}", .{}, bucket.writer());

    // duplicate payload to sentinel-terminated
    const cpayload = try ally.dupeZ(u8, bucket.items);
    defer ally.free(cpayload);

    // duplicate id to sentinel-terminated
    const key = tree.root.object.get("id").?.string;
    const ckey = try ally.dupeZ(u8, key);
    defer ally.free(ckey);

    // duplicate redis address to sentinel-terminated
    const addr: []const u8 = config.redisAddress() orelse "redis://127.0.0.1:6379";
    const caddr = try ally.dupeZ(u8, addr);
    defer ally.free(caddr);

    saveEvent(caddr, ckey, cpayload);
}

/////////////////////////////////////////////////////////////
// WASI C/interop

// (see https://github.com/ziglang/zig/issues/2274)
pub extern "outbound-redis" fn set(i32, i32, i32, i32, i32, i32, i32) void;
pub extern "outbound-redis" fn publish(i32, i32, i32, i32, i32, i32, i32) void;

var RET_AREA: [16]u8 align(8) = std.mem.zeroes([16]u8);

fn saveEvent(redis: [:0]u8, key: [:0]u8, value: [:0]u8) void {
    var result: i32 = @intCast(i32, @ptrToInt(&RET_AREA));

    // ask the host
    set(@intCast(i32, @ptrToInt(redis.ptr)), @intCast(i32, redis.len), @intCast(i32, @ptrToInt(key.ptr)), @intCast(i32, key.len), @intCast(i32, @ptrToInt(value.ptr)), @intCast(i32, value.len), result);

    const errcode = @intCast(usize, @intToPtr([*c]u8, @intCast(usize, result)).*);
    if (errcode == 0) {
        // zero means ok
        log.debug("redis set done, {s}\n", .{key});
    } else {
        // error (more detail hydration todo)
        log.err("redis set failed", .{});
    }
}
