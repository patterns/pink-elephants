const std = @import("std");
const pkcs1 = @import("pkcs1");

const cert = std.crypto.Certificate;

test "pkcs1 verify signature A" {
    var hashed_msg: [32]u8 = undefined;
    const sha = cert.Algorithm.sha256WithRSAEncryption.Hash();
    sha.hash(base_peop_TXT, &hashed_msg, .{});
    // coerce to many-pointer (for C interop)
    const c_hashed: [*]u8 = &hashed_msg;

    var b64 = std.base64.standard.Decoder;
    var decoded: [256]u8 = undefined;
    try b64.decode(&decoded, signature_peop);
    // coerce to many-pointer (for C interop)
    const c_decoded: [*]u8 = &decoded;

    try pkcs1.verify(c_hashed, c_decoded, modulus_peop, "010001");
}

test "pkcs1 verify signature B" {
    var hashed_msg: [32]u8 = undefined;
    const sha = cert.Algorithm.sha256WithRSAEncryption.Hash();
    sha.hash(base_ada_TXT, &hashed_msg, .{});
    // coerce to many-pointer (for C interop)
    const c_hashed: [*]u8 = &hashed_msg;

    var b64 = std.base64.standard.Decoder;
    var decoded: [256]u8 = undefined;
    try b64.decode(&decoded, signature_ada);
    // coerce to many-pointer (for C interop)
    const c_decoded: [*]u8 = &decoded;

    try pkcs1.verify(c_hashed, c_decoded, modulus_ada, "010001");
}

const base_peop_TXT =
    \\(request-target): post /users/oatmeal/inbox
    \\host: mastodon.social
    \\date: Sun, 30 Apr 2023 04:55:37 GMT
    \\digest: SHA-256=a9IYUmhfuVYZQnUuiqFWHhLnxk67FUjWF4W7vewjGKA=
;
const sum256_peop = "9F17D1A9F11C6AFD8AC047A4929E4A6D61CA9E9773E4A9A0FA4B6F33C6FED548";

const modulus_peop = "B2EE5CE4E8E52D18EF25F1712C6229601DCEE9E076408BC21A51F0303CB0CFD91B063412FC3E75836192499DE3BC7CC1E4C4CDFA2A7ED8C08BB77D6D54A5FD0F478C3CD0471564BE6D4BD0EE3783EE40EF7D378BABB5A9778CB8B36464D2851798017AEBAF1EACE47A78B618ECF4F1774DB701272F693AD3D938E8D5CC90EB66D6A247E5612CEDCC49EB3EE9F482377EF87B295187463182B48F7FA17863EC6543743A7F193C5248FF8011EE53AC558FBA6024951FBDA236D0504313C29DDAD6D890299D6383BE23DCF209AC8B8B9DDAF916244A3868DEFB4B4498F8ED40E7506AAE76ACFB3427CD3EE718406E34F0B9EBF5AEB1D39BAC67FCF2BB368A4CD47D";

const signature_peop = "ZooM2n+l3bYVe0lCU0V9kfBz6kLZ+LjjLPeiAoPbYT2FUQflA2ke7tZVmNGzbMKu+ILNrO9JpGlI+ai9fLKvDXbuPjurlZ6Sq9O8xgXJfuLjYY8n7qEil90dhhFa99cTDNR3RV3wk/i5cVLozoNJTJzQnGcCI5Z8MtMy7hi/W/1AR42CwCiP3CalnB0dS8S4cYdKUQnVPYX6cuCkQH7UdzcEUVQovZGZtRZ9dv3uBXlCKY+3k//haezLKtdyVYfkrGDngtS6MBz4Lp0M4LCa5XSwyUcVZ94+hx2ghoXaCiBjWtow02mrAqH9Ud8i/gnyQ9Bl18AmvmMcStcSBHrSQg==";

// Additional test case
const base_ada_TXT =
    \\(request-target): post /users/adafruit/inbox
    \\host: mastodon.cloud
    \\date: Mon, 15 May 2023 06:50:07 GMT
    \\digest: SHA-256=jNosAHjORXXd6HjZp/AFr/w+7Qub9iBwwd1JwxKgvFU=
;

const modulus_ada = "B2EE5CE4E8E52D18EF25F1712C6229601DCEE9E076408BC21A51F0303CB0CFD91B063412FC3E75836192499DE3BC7CC1E4C4CDFA2A7ED8C08BB77D6D54A5FD0F478C3CD0471564BE6D4BD0EE3783EE40EF7D378BABB5A9778CB8B36464D2851798017AEBAF1EACE47A78B618ECF4F1774DB701272F693AD3D938E8D5CC90EB66D6A247E5612CEDCC49EB3EE9F482377EF87B295187463182B48F7FA17863EC6543743A7F193C5248FF8011EE53AC558FBA6024951FBDA236D0504313C29DDAD6D890299D6383BE23DCF209AC8B8B9DDAF916244A3868DEFB4B4498F8ED40E7506AAE76ACFB3427CD3EE718406E34F0B9EBF5AEB1D39BAC67FCF2BB368A4CD47D";
const signature_ada = "cTJV1ZJxK8fVWQ/4j1TGu+pdD2XImi9RxFHOSPzBxeoTOh9IWvSRZOT5Dz4HyUeNExqp4llgXWPx0vw6g0c2YpkfpbNrCrw9F3MoRgMgJwfYzTk8hoxemC/dk51MnZb/GAvV5HWsI3drivsZD20SBOZ/Kvx64sf/FmQeMsVtAWomcxoj73pjwmAMdp82rOquC7WBH6HxUDXj5FL3qMxrB3k3sOmwdujkHOWuQj4cEruk92rtT2ddTG8iqghpa7WV0FlL0qqUcqSqcl8kaREsN9Vt2uxhJeCF7ZhY+/ECvEJCLHuEwfDhdJhgSXwv3c09gLaBfEw0hQM1aHNiDOGvGw==";
