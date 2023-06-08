const std = @import("std");

const spin = @import("../spin/lib.zig");
const vfr = @import("../verifier/verifier.zig");
const common = @import("common.zig");
const Allocator = std.mem.Allocator;
const cert = std.crypto.Certificate;
const expectStr = std.testing.expectEqualStrings;
// obtaining the verifier key usually requires a network trip so we make the step
// accept a "harvest" function which is the purpose of this test
test "Produce verifier rsa" {
    const ally = std.testing.allocator;
    var raw = common.minRawHeaders(ally) catch @panic("OutofMem");
    defer raw.deinit();
    // preverify
    try vfr.prev2(ally, raw);
    defer vfr.deinit();

    // fake public key via our custom harvester
    vfr.attachFetch(produceFromPublicKeyPEM);
    var pv = try vfr.produceVerifier(ally);
    defer pv.deinit(ally);
    var scratch_buf: [512]u8 = undefined;

    // read key's octet string (answers whether our PEM harvester ran ok)
    const pk_components = try cert.rsa.PublicKey.parseDer(pv.bits());

    // base-16: 65536 4096 256 16 1
    // which makes 65537 into 0x010001
    var txt_exponent: []u8 = try std.fmt.bufPrint(&scratch_buf, "{any}", .{std.fmt.fmtSliceHexLower(pk_components.exponent)});
    try expectStr("010001", txt_exponent);

    var txt_modulus: []u8 = try std.fmt.bufPrint(&scratch_buf, "{any}", .{std.fmt.fmtSliceHexUpper(pk_components.modulus)});
    try expectStr("C2144346C37DF21A2872F76A438D94219740B7EAB3C98FE0AF7D20BCFAADBC871035EB5405354775DF0B824D472AD10776AAC05EFF6845C9CD83089260D21D4BEFCFBA67850C47B10E7297DD504F477F79BF86CF85511E39B8125E0CAD474851C3F1B1CA0FA92FF053C67C94E8B5CFB6C63270A188BED61AA9D5F21E91AC6CC9", txt_modulus);
}

fn produceFromPublicKeyPEM(ally: std.mem.Allocator, proxy: []const u8) !vfr.ParsedVerifier {
    // skip network trip that would normally connect to proxy/provider
    _ = proxy;
    var fbs = std.io.fixedBufferStream(public_key_PEM);
    return vfr.fromPEM(ally, fbs.reader());
}

var public_key_PEM =
    \\-----BEGIN PUBLIC KEY-----
    \\MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDCFENGw33yGihy92pDjZQhl0C3
    \\6rPJj+CvfSC8+q28hxA161QFNUd13wuCTUcq0Qd2qsBe/2hFyc2DCJJg0h1L78+6
    \\Z4UMR7EOcpfdUE9Hf3m/hs+FUR45uBJeDK1HSFHD8bHKD6kv8FPGfJTotc+2xjJw
    \\oYi+1hqp1fIekaxsyQIDAQAB
    \\-----END PUBLIC KEY-----
;
