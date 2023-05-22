const std = @import("std");
pub const std_options = struct {
    pub const log_level = .debug;
};
pub fn main() void {
    std.debug.print("placeholder ", .{});
}

//comptime {
//    @export(@import("spin/lib.zig").guestHttpStart, .{ .name = "handle-http-request", .linkage = .Strong });
//    @export(@import("spin/lib.zig").canonicalAbiRealloc, .{ .name = "canonical_abi_realloc", .linkage = .Strong });
//    @export(@import("spin/lib.zig").canonicalAbiFree, .{ .name = "canonical_abi_free", .linkage = .Strong });
//}
const spn = @import("spin.zig");
const str = @import("web/strings.zig");
const status = @import("web/status.zig");
const Allocator = std.mem.Allocator;
const log = std.log;
const config = spn.Config;
const webfinger_json = @embedFile("webfinger.json");

// implement interface
const Webfinger = struct {
    pub fn eval(self: *Webfinger, ally: Allocator, w: *spn.HttpResponse, req: *spn.SpinRequest) void {
        _ = self;
        if (req.method != 0) return status.nomethod(w);

        const unknown = unknownResource(ally, req.uri);
        if (unknown) return status.bad(w);

        w.headers.put("Content-Type", "application/jrd+json") catch {
            log.err("ERROR response header", .{});
        };
        w.headers.put("Access-Control-Allow-Origin", "*") catch {
            log.err("ERROR response header", .{});
        };
        w.body.appendSlice(webfinger_json) catch {
            log.err("ERROR webfinger body", .{});
            return status.internal(w);
        };

        status.ok(w);
    }
};

// check query param 'resource'
fn unknownResource(allocator: Allocator, ur: []const u8) bool {
    const bad = true;
    var map = str.qryParams(allocator, ur);
    defer map.deinit();

    var resource: []const u8 = undefined;
    if (map.get("resource")) |val| {
        resource = val;
    } else {
        log.err("param resource is required", .{});
        return bad;
    }
    var grp = formatResource(allocator) catch {
        log.err("resource list OutOfMem", .{});
        return bad;
    };
    defer grp.deinit();
    const allowed = grp.items;
    const decoded = str.percentDecode(allocator, resource) catch {
        log.err("decode OutOfMem", .{});
        return bad;
    };
    defer allocator.free(decoded);
    for (allowed) |known| {
        log.debug("cmp {s} ({d}) to {s} ({d})", .{ known, known.len, decoded, decoded.len });

        if (std.mem.eql(u8, known, decoded)) {
            return !bad;
        }
    }

    return bad;
}

// list allowed resource values
fn formatResource(allocator: Allocator) !std.ArrayList([]const u8) {
    var all = std.ArrayList([]const u8).init(allocator);
    errdefer all.deinit();

    const who = config.selfActor() orelse "00000";
    const subd = config.siteSubdomain() orelse "00000";

    //case "acct:self@subd":
    const c1 = try std.fmt.allocPrint(allocator, "acct:{s}@{s}", .{ who, subd });
    try all.append(c1);

    //case "mailto:self@subd"
    const c2 = try std.fmt.allocPrint(allocator, "mailto:{s}@{s}", .{ who, subd });
    try all.append(c2);

    //case "https://subd"
    const c3 = try std.fmt.allocPrint(allocator, "https://{s}", .{subd});
    try all.append(c3);

    //case "https://subd/"
    const c4 = try std.fmt.allocPrint(allocator, "https://{s}/", .{subd});
    try all.append(c4);

    return all;
}
