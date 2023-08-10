const std = @import("std");

pub fn selfActor() ?[]u8 {
    return get("self_actor");
}
pub fn siteSubdomain() ?[]u8 {
    return get("site_subdomain");
}
pub fn redisAddress() ?[]u8 {
    return get("redis_address");
}
pub fn verifierProxyUri() ?[]u8 {
    return get("verifier_proxy_uri");
}
pub fn verifierProxyBearer() ?[]u8 {
    return get("verifier_proxy_bearer");
}
pub fn httpsigOrigin() ?[]u8 {
    return get("httpsig_host_origin");
}
pub fn httpsigGateway() ?[]u8 {
    return get("httpsig_host_gateway");
}

/////////////////////////////////////////////////////////////
// WASI C/interop

// (see https://github.com/ziglang/zig/issues/2274)
pub extern "spin-config" fn @"get-config"(i32, i32, i32) void;

var RET_AREA: [16]u8 align(4) = std.mem.zeroes([16]u8);

// retrieve from the component manifest
pub fn get(key: []const u8) ?[]u8 {
    var setting: []u8 = undefined;
    const ad: usize = @intFromPtr(&RET_AREA);
    const kp: usize = @intFromPtr(key.ptr);
    const address: i32 = @intCast(ad);
    const key_len: i32 = @intCast(key.len);
    const key_ptr: i32 = @intCast(kp);

    // ask the host
    @"get-config"(key_ptr, key_len, address);

    const errcode_ptr: [*c]u8 = @ptrFromInt(ad);
    const errcode_val = @as(u32, errcode_ptr.*);
    if (errcode_val == 0) {
        // zero means ok
        const start_ptr: [*c]i32 = @ptrFromInt(ad + 4);
        const start_val: usize = @intCast(start_ptr.*);
        const field_ptr: [*c]u8 = @ptrFromInt(start_val);
        const len_ptr: [*c]i32 = @ptrFromInt(ad + 8);
        const len_val: usize = @intCast(len_ptr.*);
        setting = field_ptr[0..len_val];
        // TODO dupe, and deallocate old data
        // (except, if multiple random lookups, need local cache)
    } else {
        // one means error
        std.log.err("config.get fault: (more detail todo)\n", .{});
        // TODO null until we expand the detail hydration
        return null;
    }

    return setting;
}
