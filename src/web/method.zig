const std = @import("std");

// C/host uses i32 as method which differ from std.http
pub fn rcvMethod(method: i32) std.http.Method {
    switch (method) {
        0 => return .GET,
        1 => return .POST,
        2 => return .PUT,
        3 => return .DELETE,
        4 => return .PATCH,
        5 => return .HEAD,
        6 => return .OPTIONS,
        else => unreachable,
    }
}
