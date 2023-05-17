const std = @import("std");
const c = @cImport({
    @cInclude("mbedtls/bignum.h");
    @cInclude("mbedtls/md.h");
    @cInclude("mbedtls/rsa.h");
});

// Entry point for zig logic to call into MbedTLS Crypto (C) library
pub fn verify(
    hashed: [*]u8,
    sig: [*]const u8,
    N: [:0]const u8,
    E: [:0]const u8,
) !void {
    //hashed is the sha256 sum of message (32 bytes assumed here)
    //sig is the signature supplied to us in the header

    // rsa context is the MbedTLS abstraction layer for a verifier
    var rsa_context: c.mbedtls_rsa_context = undefined;
    var mpi_n: c.mbedtls_mpi = undefined;
    var mpi_e: c.mbedtls_mpi = undefined;
    c.mbedtls_rsa_init(&rsa_context);
    c.mbedtls_mpi_init(&mpi_n);
    c.mbedtls_mpi_init(&mpi_e);
    defer c.mbedtls_rsa_free(&rsa_context);
    defer c.mbedtls_mpi_free(&mpi_n);
    defer c.mbedtls_mpi_free(&mpi_e);

    // read hexadecimal form of N and E
    const read_n = c.mbedtls_mpi_read_string(&mpi_n, 16, N);
    const read_e = c.mbedtls_mpi_read_string(&mpi_e, 16, E);
    if (read_n != 0 or read_e != 0) return error.PKCS1VerifyRead;

    // assign N and E public key fields
    _ = c.mbedtls_rsa_import(&rsa_context, &mpi_n, null, null, null, &mpi_e);
    const ready = c.mbedtls_rsa_complete(&rsa_context);
    if (ready != 0) return error.PKCS1VerifyInit;

    // invoke MbedTLS (C) lib's verify
    const ret = c.mbedtls_rsa_pkcs1_verify(
        &rsa_context,
        c.MBEDTLS_MD_SHA256,
        32,
        hashed,
        sig,
    );

    if (ret != 0) return error.PKCS1VerifyNotPass;
}
