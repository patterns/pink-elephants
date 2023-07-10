const std = @import("std");
// export symbols (in 0.11 see zig/issues/14139)
const export_names = [_][]const u8{
    "canonical_abi_free",
    "canonical_abi_realloc",
    "handle-http-request",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const project_level = b.addOptions();

    // enable clib cross-compilation
    const lib = b.addStaticLibrary(.{
        .name = "pkcs1verify",
        .target = target,
        .optimize = optimize,
    });

    const libroot = "./deps/mbedtls/library/";
    const cflags = [_][]const u8{
        "-Ideps/config",
        "-DMBEDTLS_CONFIG_FILE=\"pkcs1verify_config.h\"",
        "-std=c99",
        "-Wall",
        "-Wextra",
        "-Wwrite-strings",
        "-Wpointer-arith",
        "-Wimplicit-fallthrough",
        "-Wshadow",
        "-Wvla",
        "-Wformat=2",
        "-Wno-format-nonliteral",
        "-Wmissing-declarations",
        "-Wmissing-prototypes",
        "-Wdocumentation",
        "-Wno-documentation-deprecated-sync",
        "-Wunreachable-code",
    };

    // subset from mbedtls_config.h for pkcs1v15 verify only
    lib.defineCMacro("MBEDTLS_ENTROPY_C", "1");
    lib.defineCMacro("MBEDTLS_HMAC_DRBG_C", "1");
    lib.defineCMacro("MBEDTLS_MD_C", "1");
    lib.defineCMacro("MBEDTLS_SHA512_C", "1");
    lib.defineCMacro("MBEDTLS_SHA256_C", "1");
    lib.defineCMacro("MBEDTLS_RSA_C", "1");
    lib.defineCMacro("MBEDTLS_PKCS1_V15", "1");
    lib.defineCMacro("MBEDTLS_BIGNUM_C", "1");
    lib.defineCMacro("MBEDTLS_OID_C", "1");
    lib.defineCMacro("MBEDTLS_ERROR_C", "1");
    lib.defineCMacro("MBEDTLS_PLATFORM_C", "1");

    const sources = [_][]const u8{
        libroot ++ "entropy.c",
        libroot ++ "hmac_drbg.c",
        libroot ++ "md.c",
        libroot ++ "sha512.c",
        libroot ++ "sha256.c",
        libroot ++ "rsa.c",
        libroot ++ "rsa_alt_helpers.c",
        libroot ++ "bignum.c",
        libroot ++ "bignum_core.c",
        libroot ++ "bignum_mod.c",
        libroot ++ "bignum_mod_raw.c",
        libroot ++ "oid.c",
        libroot ++ "constant_time.c",
        libroot ++ "platform_util.c",
        libroot ++ "error.c",
        libroot ++ "hash_info.c",
        libroot ++ "platform.c",
    };

    lib.addCSourceFiles(&sources, &cflags);
    lib.linkLibC();
    lib.addIncludePath("./deps/mbedtls/include");
    lib.addIncludePath(libroot);
    b.installArtifact(lib);

    // internal module for zig code to consume
    const pkcs1 = b.createModule(
        .{ .source_file = .{ .path = "src/verify/pkcs1.zig" } },
    );

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    unit_tests.linkLibC();
    unit_tests.linkLibrary(lib);
    unit_tests.addIncludePath("./deps/mbedtls/include");
    unit_tests.addModule("pkcs1", pkcs1);

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // define a redis prefix which can be the filter for scanning keys
    project_level.addOption([]const u8, "redis_prefix", "peop");

    // inbox component
    {
        const inexe = b.addExecutable(.{
            .name = "inbox",
            .root_source_file = .{ .path = "src/inbox.zig" },
            .target = target,
            .optimize = optimize,
        });
        inexe.linkLibC();
        inexe.linkLibrary(lib);
        inexe.addIncludePath("./deps/mbedtls/include");
        inexe.addModule("pkcs1", pkcs1);
        inexe.single_threaded = true;
        inexe.export_symbol_names = &export_names;
        inexe.addOptions("build_options", project_level);
        b.installArtifact(inexe);
    }
    // outbox component
    {
        const obexe = b.addExecutable(.{
            .name = "outbox",
            .root_source_file = .{ .path = "src/outbox.zig" },
            .target = target,
            .optimize = optimize,
        });
        obexe.linkLibC();
        obexe.linkLibrary(lib);
        obexe.addIncludePath("./deps/mbedtls/include");
        obexe.addModule("pkcs1", pkcs1);
        obexe.single_threaded = true;
        obexe.export_symbol_names = &export_names;
        obexe.addOptions("build_options", project_level);
        b.installArtifact(obexe);
    }

    // webfinger component
    {
        const wfexe = b.addExecutable(.{
            .name = "webfinger",
            .root_source_file = .{ .path = "src/webfinger.zig" },
            .target = target,
            .optimize = optimize,
        });
        wfexe.single_threaded = true;
        wfexe.export_symbol_names = &export_names;
        b.installArtifact(wfexe);
    }

    // actor component
    {
        const acexe = b.addExecutable(.{
            .name = "actor",
            .root_source_file = .{ .path = "src/actor.zig" },
            .target = target,
            .optimize = optimize,
        });
        acexe.single_threaded = true;
        acexe.export_symbol_names = &export_names;
        b.installArtifact(acexe);
    }
}
