const std = @import("std");
// export symbols (in 0.11 see zig/issues/14139)
const export_names = [_][]const u8 {
        "canonical_abi_free",
        "canonical_abi_realloc",
        "handle-http-request",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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
        .{ .source_file = .{ .path = "src/pkcs1.zig" }},
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

    _ = b.addRunArtifact(unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    _ = b.step("test", "Run unit tests");




    // inbox component
    {
    const exe = b.addExecutable(.{
        .name = "inbox",
        .root_source_file = .{ .path = "src/inbox.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    exe.linkLibrary(lib);
    exe.addIncludePath("./deps/mbedtls/include");
    exe.addModule("pkcs1", pkcs1);
    exe.single_threaded = true;
    exe.export_symbol_names = &export_names;
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
    }

}

