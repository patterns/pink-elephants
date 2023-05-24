const std = @import("std");
const spin = @import("spin/lib.zig");
const str = @import("web/strings.zig");
const status = @import("web/status.zig");

const Allocator = std.mem.Allocator;
const log = std.log;
comptime {
    spin.handle(outboxScript);
}
pub fn main() void {
    std.debug.print("placeholder ", .{});
}

fn outboxScript(ally: Allocator, w: *spin.HttpResponse, r: *spin.Request) void {

    //TODO verify signature
    //     verify timestamp

    //TODO limit body content to 1MB
    var tree = str.toTree(ally, r.body) catch {
        log.err("unexpected json format\n", .{});
        return status.unprocessable(w);
    };
    defer tree.deinit();

    // capture for now (build processing later)
    spin.redis.enqueue(ally, tree) catch {
        log.err("save failed", .{});
        return status.internal(w);
    };

    w.headers.put("Content-Type", "application/json") catch {
        log.err("response header, OutOfMem", .{});
    };

    status.ok(w);
}
