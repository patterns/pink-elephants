const std = @import("std");
const config = @import("config.zig");
const redis_prefix = @import("build_options").redis_prefix;

// add _job_ item that will be picked up by a _worker_
pub fn enqueue(ally: std.mem.Allocator, content: std.json.Value) !void {
    var bucket = std.ArrayList(u8).init(ally);
    defer bucket.deinit();
    try std.json.stringify(content, .{}, bucket.writer());

    // duplicate payload to sentinel-terminated
    const cpayload = try ally.dupeZ(u8, bucket.items);
    defer ally.free(cpayload);

    var sequence_num = try pseudoSeq(ally, content.object.get("id"), "");
    defer ally.free(sequence_num);

    // duplicate redis address to sentinel-terminated
    const addr: []const u8 = config.redisAddress() orelse "redis://127.0.0.1:6379";
    const caddr = try ally.dupeZ(u8, addr);
    defer ally.free(caddr);

    saveEvent(caddr, sequence_num, cpayload);
}

// capture extra request detail to debug/tests
pub fn debugText(ally: std.mem.Allocator, rcv: anytype) !void {
    var bucket = std.ArrayList(u8).init(ally);
    defer bucket.deinit();

    try bucket.appendSlice(rcv.body);

    // inject debug marker
    try bucket.appendSlice("##DEBUG##");
    try rcv.headers.format("{s}", .{}, bucket.writer());

    // duplicate payload to sentinel-terminated
    const cpayload = try ally.dupeZ(u8, bucket.items);
    defer ally.free(cpayload);

    var sequence_num = try pseudoSeq(ally, null, "");
    defer ally.free(sequence_num);

    // duplicate redis address to sentinel-terminated
    const addr: []const u8 = config.redisAddress() orelse "redis://127.0.0.1:6379";
    const caddr = try ally.dupeZ(u8, addr);
    defer ally.free(caddr);

    saveEvent(caddr, sequence_num, cpayload);
}
pub fn failureText(ally: std.mem.Allocator, rcv: anytype) !void {
    //todo refactor to reduce since pseudoSeq is the only diff

    var bucket = std.ArrayList(u8).init(ally);
    defer bucket.deinit();

    try bucket.appendSlice(rcv.body);

    // inject debug marker
    try bucket.appendSlice("##DEBUG##");
    try rcv.headers.format("{s}", .{}, bucket.writer());

    // duplicate payload to sentinel-terminated
    const cpayload = try ally.dupeZ(u8, bucket.items);
    defer ally.free(cpayload);

    var sequence_num = try pseudoSeq(ally, null, "verify");
    defer ally.free(sequence_num);

    // duplicate redis address to sentinel-terminated
    const addr: []const u8 = config.redisAddress() orelse "redis://127.0.0.1:6379";
    const caddr = try ally.dupeZ(u8, addr);
    defer ally.free(caddr);

    saveEvent(caddr, sequence_num, cpayload);
}
const streq = std.ascii.eqlIgnoreCase;
// duplicate id to sentinel-terminated
fn pseudoSeq(ally: std.mem.Allocator, id: ?std.json.Value, fail: []const u8) ![:0]u8 {
    //TODO want the SHA checksum from the header for uniqueness

    var pre: [:0]const u8 = redis_prefix ++ ":activity";
    if (fail.len != 0) {
        // group verify failures together to troubleshoot
        if (streq("verify", fail)) {
            pre = redis_prefix ++ ":fault";
        }
    }
    if (id) |val| {
        return try std.fmt.allocPrintZ(ally, "{s}:{s}", .{ pre, val.string });
    }
    // fallback pseudo-id
    return try std.fmt.allocPrintZ(ally, "{s}:{d}", .{ pre, std.time.milliTimestamp() });
}

/////////////////////////////////////////////////////////////
// WASI C/interop

// (see https://github.com/ziglang/zig/issues/2274)
pub extern "outbound-redis" fn set(i32, i32, i32, i32, i32, i32, i32) void;
pub extern "outbound-redis" fn publish(i32, i32, i32, i32, i32, i32, i32) void;

var RET_AREA: [16]u8 align(8) = std.mem.zeroes([16]u8);

fn saveEvent(redis: [:0]u8, key: [:0]u8, value: [:0]u8) void {
    const ad: usize = @intFromPtr(&RET_AREA);
    const rp: usize = @intFromPtr(redis.ptr);
    const kp: usize = @intFromPtr(key.ptr);
    const vp: usize = @intFromPtr(value.ptr);
    const address: i32 = @intCast(ad);
    const server_len: i32 = @intCast(redis.len);
    const server_ptr: i32 = @intCast(rp);
    const key_len: i32 = @intCast(key.len);
    const key_ptr: i32 = @intCast(kp);
    const val_len: i32 = @intCast(value.len);
    const val_ptr: i32 = @intCast(vp);

    // ask the host
    set(server_ptr, server_len, key_ptr, key_len, val_ptr, val_len, address);

    const code_ptr: [*c]u8 = @ptrFromInt(ad);
    const errcode: u8 = @intCast(code_ptr.*);
    if (errcode == 0) {
        // zero means ok
        std.log.debug("redis.set, {s}\x0A", .{key});
    } else {
        // error (more detail hydration todo)
        std.log.err("redis.set fault", .{});
    }
}
