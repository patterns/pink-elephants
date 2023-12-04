const std = @import("std");
const spin = @import("spin/lib.zig");
const str = @import("web/strings.zig");
const status = @import("web/status.zig");

const Allocator = std.mem.Allocator;
const log = std.log;
comptime {
    spin.handle(actorScript);
}
pub fn main() void {
    std.debug.print("placeholder ", .{});
}

const actor_json = @embedFile("actor.json");
const followers_json = @embedFile("followers.json");
const following_json = @embedFile("following.json");
fn actorScript(ally: Allocator, ret: anytype, rcv: anytype) void {
    if (rcv.method != .GET) return status.nomethod();

    ret.headers.append("Content-Type", "application/json") catch {
        log.err("Header fault in act", .{});
    };
    ret.headers.append("Access-Control-Allow-Origin", "*") catch {
        log.err("Header fault in act", .{});
    };

    // ask host for actor setting
    const who = spin.config.selfActor() orelse "00000";
    const subd = spin.config.siteSubdomain() orelse "00000";
    const branch = unknownActor(ally, rcv.uri, who) catch {
        log.err("allocPrint, OutOfMem", .{});
        return status.internal();
    };
    switch (branch) {
        .actor => {
            const replaced = str.fmtJson(ally, actor_json, who, subd) catch {
                log.err("Substituion fault in act", .{});
                return status.internal();
            };
            defer ally.free(replaced);
            ret.body.appendSlice(replaced) catch {
                log.err("actor, OutOfMem", .{});
                return status.internal();
            };
        },

        .followers => {
            const replaced = str.fmtJson(ally, followers_json, who, subd) catch {
                log.err("Substituion fault in followers", .{});
                return status.internal();
            };
            defer ally.free(replaced);
            ret.body.appendSlice(replaced) catch {
                log.err("followers, OutOfMem", .{});
                return status.internal();
            };
        },

        .following => {
            const replaced = str.fmtJson(ally, following_json, who, subd) catch {
                log.err("Substituion fault in followers", .{});
                return status.internal();
            };
            defer ally.free(replaced);
            ret.body.appendSlice(replaced) catch {
                log.err("following, OutOfMem", .{});
                return status.internal();
            };
        },

        .empty => return status.notfound(),
    }

    status.ok();
}

// "static" actor has limited formats
fn unknownActor(allocator: Allocator, ur: []const u8, who: []const u8) !FormatOption {
    const upath = str.toPath(ur);

    // request for actor
    const base = try std.fmt.allocPrint(allocator, "/u/{s}", .{who});
    defer allocator.free(base);
    if (std.mem.eql(u8, upath, base)) {
        return FormatOption.actor;
    }

    // request for their followers
    const flow = try std.fmt.allocPrint(allocator, "{s}/followers", .{base});
    defer allocator.free(flow);
    if (std.mem.startsWith(u8, upath, flow)) {
        return FormatOption.followers;
    }

    // request for who-they-follow
    const fwng = try std.fmt.allocPrint(allocator, "{s}/following", .{base});
    defer allocator.free(fwng);
    if (std.mem.startsWith(u8, upath, fwng)) {
        return FormatOption.following;
    }

    return FormatOption.empty;
}

const FormatOption = enum { empty, actor, followers, following };
