test "Web" {
    _ = @import("web/phi.zig");
}
test "Verifier" {
    _ = @import("tests/verifier_tests.zig");
}
test "MbedTLS" {
    _ = @import("tests/pkcs1_tests.zig");
}
