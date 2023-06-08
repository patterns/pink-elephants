////const std = @import("std");

test {
    ////std.testing.refAllDecls(@This());

    _ = @import("tests/pkcs1_tests.zig");
    _ = @import("tests/verifier_01.zig");
    _ = @import("tests/verifier_02.zig");
    _ = @import("tests/verifier_03.zig");
}
