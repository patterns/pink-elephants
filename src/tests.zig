////const std = @import("std");

test {
    ////std.testing.refAllDecls(@This());

    _ = @import("tests/pkcs1_tests.zig");
    _ = @import("tests/verifier_01.zig");
    _ = @import("tests/verifier_02.zig");
    _ = @import("tests/verifier_03.zig");
    _ = @import("tests/verifier_04.zig");
    _ = @import("tests/verifier_05.zig");
    _ = @import("tests/verifier_06.zig");
    _ = @import("tests/verifier_07.zig");
    _ = @import("tests/verifier_08.zig");
}
