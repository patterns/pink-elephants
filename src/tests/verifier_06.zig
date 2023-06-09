const std = @import("std");

const spin = @import("../spin/lib.zig");
const vrf = @import("../verify/verifier.zig");
const common = @import("common.zig");
const Allocator = std.mem.Allocator;
const cert = std.crypto.Certificate;
const expectStr = std.testing.expectEqualStrings;
// obtaining the verifier key usually requires a network trip so we make the step
// accept a "harvest" function which is the purpose of this test
test "Produce verifier eff" {
    const ally = std.testing.allocator;
    var raw = common.minRawHeaders(ally) catch @panic("OutofMem");
    defer raw.deinit();
    // preverify
    try vrf.prev2(ally, raw);
    defer vrf.deinit();

    // fake public key via our custom harvester
    vrf.attachFetch(produceFromEFFPEM);
    var pv = try vrf.produceVerifier(ally);
    defer pv.deinit(ally);
    var scratch_buf: [512]u8 = undefined;
    // read key bitstring
    const pk_components = try cert.rsa.PublicKey.parseDer(pv.bits());

    var txt_exponent: []u8 = try std.fmt.bufPrint(&scratch_buf, "{any}", .{std.fmt.fmtSliceHexLower(pk_components.exponent)});
    try expectStr("010001", txt_exponent);

    var txt_modulus: []u8 = try std.fmt.bufPrint(&scratch_buf, "{any}", .{std.fmt.fmtSliceHexUpper(pk_components.modulus)});
    try expectStr("9E1C944BF0F66D0F6D3188C413A51B8F4D1BEF39FC2C887F65AFD661FC8D01410DB7A4B130E0C0E043DA6CE0648F4761F994C19ED47281AABC0451C4E86B8C6376BF566C6D75629070C106F26A42D3B94C947B3DC6978709E669CEC04DDD230E5A9EA3EFF9440FFAF36D5D510714809B79824787A513456CA4F6994DB361FFAC12C81D0E84B6154D4CBB18611E757848D160C392446AF950767ECCCD141E50A7764842ABB8D7DEE483C5B3031A129A9FEB624ADE35409799C5E9AE14D9AEB80EADD57359174FE825E390EFCAFF315E652EABCED0239CCCAE32FF014421E47E7B61C73E2F6B5907A3A91546BD75EED39A04305AC459A6982ECF2AA4D1BEA5CF6D", txt_modulus);
}

fn produceFromEFFPEM(ally: std.mem.Allocator, proxy: []const u8) !vrf.ParsedVerifier {
    // skip network trip that would normally connect to proxy/provider
    _ = proxy;
    var fbs = std.io.fixedBufferStream(public_eff_PEM);
    return vrf.fromPEM(ally, fbs.reader());
}

const public_eff_PEM =
    \\-----BEGIN PUBLIC KEY-----
    \\MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnhyUS/D2bQ9tMYjEE6Ub
    \\j00b7zn8LIh/Za/WYfyNAUENt6SxMODA4EPabOBkj0dh+ZTBntRygaq8BFHE6GuM
    \\Y3a/VmxtdWKQcMEG8mpC07lMlHs9xpeHCeZpzsBN3SMOWp6j7/lED/rzbV1RBxSA
    \\m3mCR4elE0VspPaZTbNh/6wSyB0OhLYVTUy7GGEedXhI0WDDkkRq+VB2fszNFB5Q
    \\p3ZIQqu4197kg8WzAxoSmp/rYkreNUCXmcXprhTZrrgOrdVzWRdP6CXjkO/K/zFe
    \\ZS6rztAjnMyuMv8BRCHkfnthxz4va1kHo6kVRr117tOaBDBaxFmmmC7PKqTRvqXP
    \\bQIDAQAB
    \\-----END PUBLIC KEY-----
;
