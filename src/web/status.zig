const std = @import("std");
const ret = @import("../spin/wasi.zig");

// here we rely on the returns overlay defined from wasi namespace
// which exposes the status "set-ter". Then we can in turn, have
// convenience wrappers.

pub fn nomethod() void {
    ret.status(std.http.Status.method_not_allowed);
}

pub fn bad() void {
    ret.status(std.http.Status.bad_request);
}

pub fn internal() void {
    ret.status(std.http.Status.internal_server_error);
}

pub fn notfound() void {
    ret.status(std.http.Status.not_found);
}

pub fn forbidden() void {
    ret.status(std.http.Status.forbidden);
}

pub fn toolarge() void {
    ret.status(std.http.Status.payload_too_large);
}

pub fn unprocessable() void {
    ret.status(std.http.Status.unprocessable_entity);
}

pub fn noaccept() void {
    ret.status(std.http.Status.not_acceptable);
}

pub fn expectation() void {
    ret.status(std.http.Status.expectation_failed);
}

pub fn dependency() void {
    ret.status(std.http.Status.failed_dependency);
}

pub fn unavailable() void {
    ret.status(std.http.Status.service_unavailable);
}

pub fn storage() void {
    ret.status(std.http.Status.insufficient_storage);
}

pub fn nocontent() void {
    ret.status(std.http.Status.no_content);
}

pub fn ok() void {
    ret.status(std.http.Status.ok);
}
