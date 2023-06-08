const std = @import("std");

const spin = @import("../spin/lib.zig");
const vfr = @import("../verifier/verifier.zig");
//const common = @import("common.zig");
const Allocator = std.mem.Allocator;
const cert = std.crypto.Certificate;
const expectStr = std.testing.expectEqualStrings;

test "verify peop" {
    const ally = std.testing.allocator;
    var raw = peopRawHeaders(ally) catch @panic("OutofMem");
    defer raw.deinit();

    var sim_rcv_request = .{
        .method = spin.http.Verb.post,
        .uri = "/users/oatmeal/inbox",
        .headers = raw,
        .body = undefined,
    };
    // preverify
    try vfr.prev2(ally, raw);
    defer vfr.deinit();

    // peop public key
    vfr.attachFetch(produceFromPeopPEM);
    var pv = try vfr.produceVerifier(ally);
    defer pv.deinit(ally);
    var scratch_buf: [512]u8 = undefined;
    // read key bitstring
    const pk_components = try cert.rsa.PublicKey.parseDer(pv.bits());
    var txt_exponent: []u8 = try std.fmt.bufPrint(&scratch_buf, "{any}", .{std.fmt.fmtSliceHexLower(pk_components.exponent)});
    try expectStr("010001", txt_exponent);
    var txt_modulus: []u8 = try std.fmt.bufPrint(&scratch_buf, "{any}", .{std.fmt.fmtSliceHexUpper(pk_components.modulus)});
    try expectStr(modulus_peop, txt_modulus);

    // base input check
    const base = try vfr.fmtBase(sim_rcv_request);
    try expectStr(base, base_peop_TXT);

    //var hashed_msg: [32]u8 = undefined;
    // sha256 sum check
    //try proof.hashed(cert.Algorithm.sha256WithRSAEncryption.Hash(),
    //    base,
    //    cert.Parsed.PubKeyAlgo.rsaEncryption,
    //    &hashed_msg);
    //const txt_hashed: []u8 = try fmt.bufPrint(&scratch_buf, "{any}",
    //    .{fmt.fmtSliceHexUpper(&hashed_msg)});
    //try expectStr(sum256_peop, txt_hashed);

    ////const result = try vfr.bySigner(ally, base);
    ////try expect(result == true);
}

// (follow) request fields
fn peopRawHeaders(ally: Allocator) !std.http.Headers {
    var h2 = std.http.Headers.init(ally);
    try h2.append("host", "mastodon.social");
    try h2.append("date", "Sun, 30 Apr 2023 04:55:37 GMT");

    try h2.append("digest", "SHA-256=a9IYUmhfuVYZQnUuiqFWHhLnxk67FUjWF4W7vewjGKA=");

    try h2.append(
        "signature",
        "keyId=\"Testfoll\",algorithm=\"rsa-sha256\",headers=\"(request-target) host date digest\",signature=\"ZooM2n+l3bYVe0lCU0V9kfBz6kLZ+LjjLPeiAoPbYT2FUQflA2ke7tZVmNGzbMKu+ILNrO9JpGlI+ai9fLKvDXbuPjurlZ6Sq9O8xgXJfuLjYY8n7qEil90dhhFa99cTDNR3RV3wk/i5cVLozoNJTJzQnGcCI5Z8MtMy7hi/W/1AR42CwCiP3CalnB0dS8S4cYdKUQnVPYX6cuCkQH7UdzcEUVQovZGZtRZ9dv3uBXlCKY+3k//haezLKtdyVYfkrGDngtS6MBz4Lp0M4LCa5XSwyUcVZ94+hx2ghoXaCiBjWtow02mrAqH9Ud8i/gnyQ9Bl18AmvmMcStcSBHrSQg==\"",
    );

    return h2;
}

fn produceFromPeopPEM(ally: std.mem.Allocator, proxy: []const u8) !vfr.ParsedVerifier {
    // skip network trip that would normally connect to proxy/provider
    _ = proxy;
    var fbs = std.io.fixedBufferStream(public_peop_PEM);
    return vfr.fromPEM(ally, fbs.reader());
}

const public_peop_PEM =
    \\-----BEGIN PUBLIC KEY-----
    \\MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsu5c5OjlLRjvJfFxLGIp
    \\YB3O6eB2QIvCGlHwMDywz9kbBjQS/D51g2GSSZ3jvHzB5MTN+ip+2MCLt31tVKX9
    \\D0eMPNBHFWS+bUvQ7jeD7kDvfTeLq7Wpd4y4s2Rk0oUXmAF6668erOR6eLYY7PTx
    \\d023AScvaTrT2Tjo1cyQ62bWokflYSztzEnrPun0gjd++HspUYdGMYK0j3+heGPs
    \\ZUN0On8ZPFJI/4AR7lOsVY+6YCSVH72iNtBQQxPCndrW2JApnWODviPc8gmsi4ud
    \\2vkWJEo4aN77S0SY+O1A51Bqrnas+zQnzT7nGEBuNPC56/WusdObrGf88rs2ikzU
    \\fQIDAQAB
    \\-----END PUBLIC KEY-----
;

const base_peop_TXT =
    \\(request-target): post /users/oatmeal/inbox
    \\host: mastodon.social
    \\date: Sun, 30 Apr 2023 04:55:37 GMT
    \\digest: SHA-256=a9IYUmhfuVYZQnUuiqFWHhLnxk67FUjWF4W7vewjGKA=
;
const sum256_peop = "9F17D1A9F11C6AFD8AC047A4929E4A6D61CA9E9773E4A9A0FA4B6F33C6FED548";
const modulus_peop = "B2EE5CE4E8E52D18EF25F1712C6229601DCEE9E076408BC21A51F0303CB0CFD91B063412FC3E75836192499DE3BC7CC1E4C4CDFA2A7ED8C08BB77D6D54A5FD0F478C3CD0471564BE6D4BD0EE3783EE40EF7D378BABB5A9778CB8B36464D2851798017AEBAF1EACE47A78B618ECF4F1774DB701272F693AD3D938E8D5CC90EB66D6A247E5612CEDCC49EB3EE9F482377EF87B295187463182B48F7FA17863EC6543743A7F193C5248FF8011EE53AC558FBA6024951FBDA236D0504313C29DDAD6D890299D6383BE23DCF209AC8B8B9DDAF916244A3868DEFB4B4498F8ED40E7506AAE76ACFB3427CD3EE718406E34F0B9EBF5AEB1D39BAC67FCF2BB368A4CD47D";
