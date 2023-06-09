const std = @import("std");
const spin = @import("spin/lib.zig");
const str = @import("web/strings.zig");
const status = @import("web/status.zig");

const Allocator = std.mem.Allocator;
const log = std.log;

comptime {
    spin.handle(webfingerScript);
}
pub fn main() void {
    std.debug.print("placeholder ", .{});
}

const webfinger_json = @embedFile("webfinger.json");
fn webfingerScript(ally: Allocator, ret: anytype, rcv: anytype) void {
    // component level configuration settings for activitypub
    const who = spin.config.selfActor() orelse "00000";
    const subd = spin.config.siteSubdomain() orelse "00000";

    if (rcv.method != .GET) return status.nomethod();

    const unknown = unknownResource(ally, rcv.uri, who, subd);
    if (unknown) return status.bad();

    ret.headers.append("Content-Type", "application/jrd+json") catch {
        log.err("Header fault in wf", .{});
    };
    ret.headers.append("Access-Control-Allow-Origin", "*") catch {
        log.err("Header fault in wf", .{});
    };

    const replaced = str.fmtJson(ally, webfinger_json, who, subd) catch {
        log.err("Substitution fault in wf", .{});
        return status.internal();
    };
    defer ally.free(replaced);
    ret.body.appendSlice(replaced) catch {
        log.err("Append fault in wf", .{});
        return status.internal();
    };

    status.ok();
}

// check query param 'resource'
fn unknownResource(ally: Allocator, ur: []const u8, who: []const u8, subd: []const u8) bool {
    const bad = true;
    var map = str.qryParams(ally, ur);
    defer map.deinit();

    var resource: []const u8 = undefined;
    if (map.get("resource")) |val| {
        resource = val;
    } else {
        log.err("param resource is required", .{});
        return bad;
    }
    var grp = formatResource(ally, who, subd) catch {
        log.err("resource list OutOfMem", .{});
        return bad;
    };
    defer grp.deinit();
    const allowed = grp.items;
    const decoded = str.percentDecode(ally, resource) catch {
        log.err("decode OutOfMem", .{});
        return bad;
    };
    defer ally.free(decoded);
    for (allowed) |known| {
        log.debug("cmp {s} ({d}) to {s} ({d})", .{ known, known.len, decoded, decoded.len });

        if (std.mem.eql(u8, known, decoded)) {
            return !bad;
        }
    }

    return bad;
}

// list allowed resource values
fn formatResource(ally: Allocator, who: []const u8, subd: []const u8) !std.ArrayList([]const u8) {
    var all = std.ArrayList([]const u8).init(ally);
    errdefer all.deinit();

    //case "acct:self@subd":
    const c1 = try std.fmt.allocPrint(ally, "acct:{s}@{s}", .{ who, subd });
    try all.append(c1);

    //case "mailto:self@subd"
    const c2 = try std.fmt.allocPrint(ally, "mailto:{s}@{s}", .{ who, subd });
    try all.append(c2);

    //case "https://subd"
    const c3 = try std.fmt.allocPrint(ally, "https://{s}", .{subd});
    try all.append(c3);

    //case "https://subd/"
    const c4 = try std.fmt.allocPrint(ally, "https://{s}/", .{subd});
    try all.append(c4);

    return all;
}
