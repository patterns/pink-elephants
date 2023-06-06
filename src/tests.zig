////const std = @import("std");

test {
    ////std.testing.refAllDecls(@This());

    _ = @import("tests/verifier_tests.zig");
    _ = @import("tests/pkcs1_tests.zig");
}
