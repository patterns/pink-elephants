const std = @import("std");

const spin = @import("../spin/lib.zig");
const vrf = @import("../verify/verifier.zig");
const common = @import("common.zig");
const Allocator = std.mem.Allocator;
const cert = std.crypto.Certificate;
const expectStr = std.testing.expectEqualStrings;
// obtaining the verifier key usually requires a network trip so we make the step
// accept a "harvest" function which is the purpose of this test
test "Produce verifier adafruit" {
    const ally = std.testing.allocator;
    var raw = common.minRawHeaders(ally) catch @panic("OutofMem");
    defer raw.deinit();
    // preverify
    try vrf.prev2(ally, raw);
    defer vrf.deinit();

    // fake public key via our custom harvester
    vrf.attachFetch(produceFromAdafruitPEM);
    var pv = try vrf.produceVerifier(ally);
    defer pv.deinit(ally);
    var scratch_buf: [512]u8 = undefined;
    // read key bitstring
    const pk_components = try cert.rsa.PublicKey.parseDer(pv.bits());

    var txt_exponent: []u8 = try std.fmt.bufPrint(&scratch_buf, "{any}", .{std.fmt.fmtSliceHexLower(pk_components.exponent)});
    try expectStr("010001", txt_exponent);

    var txt_modulus: []u8 = try std.fmt.bufPrint(&scratch_buf, "{any}", .{std.fmt.fmtSliceHexUpper(pk_components.modulus)});
    try expectStr("B2906B60D93EBD25A2F2D691B7CAD614BCA0FB2E5B0B8640FA621719DDD12C49B47E35F38BDD0DE221F133ACF0B5D10ED5D2DBBA3F0A0DBA42E6B0E910C7F13019AF989569BDB55B65C94E50AA4D2C829D90F98F14A0C23693548064A4FAAF0821291A017EA8DDB02EF666A0CBA8B1B4DA3C50161AF8892A3890DB7A18750B981FFF8444CAEB92C985C8AA395637A0281C15609434E4C46C884369231513E1D54E56AE59AED8EFEF837187F731E7FBE8B3E6F2A7326F489DCAFC4EAAA4942BA494D5F16FF708096A255933882DA9D85A5313DD050EBD6EF26891967BD3E1EF3E7D4AA2864D07E719F318D45FB92CB3B42A18EB0437390C2332F85E123F65D733", txt_modulus);
}

fn produceFromAdafruitPEM(ally: std.mem.Allocator, proxy: []const u8) !vrf.ParsedVerifier {
    // skip network trip that would normally connect to proxy/provider
    _ = proxy;
    var fbs = std.io.fixedBufferStream(public_adafruit_PEM);
    return vrf.fromPEM(ally, fbs.reader());
}

const public_adafruit_PEM =
    \\-----BEGIN PUBLIC KEY-----
    \\MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAspBrYNk+vSWi8taRt8rW
    \\FLyg+y5bC4ZA+mIXGd3RLEm0fjXzi90N4iHxM6zwtdEO1dLbuj8KDbpC5rDpEMfx
    \\MBmvmJVpvbVbZclOUKpNLIKdkPmPFKDCNpNUgGSk+q8IISkaAX6o3bAu9magy6ix
    \\tNo8UBYa+IkqOJDbehh1C5gf/4REyuuSyYXIqjlWN6AoHBVglDTkxGyIQ2kjFRPh
    \\1U5Wrlmu2O/vg3GH9zHn++iz5vKnMm9Incr8TqqklCuklNXxb/cICWolWTOILanY
    \\WlMT3QUOvW7yaJGWe9Ph7z59SqKGTQfnGfMY1F+5LLO0KhjrBDc5DCMy+F4SP2XX
    \\MwIDAQAB
    \\-----END PUBLIC KEY-----
;
