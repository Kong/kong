"""An openssl build file based on a snippet found in the github issue:
https://github.com/bazelbuild/rules_foreign_cc/issues/337

Note that the $(PERL) "make variable" (https://docs.bazel.build/versions/main/be/make-variables.html)
is populated by the perl toolchain provided by rules_perl.
"""

load("@rules_foreign_cc//foreign_cc:defs.bzl", "configure_make")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

# Read https://wiki.openssl.org/index.php/Compilation_and_Installation

CONFIGURE_OPTIONS = select({
    "@kong//:aarch64-linux-glibc-cross": [
        "linux-aarch64",
    ],
    "@kong//:x86_64-linux-glibc-cross": [
        "linux-x86_64",
    ],
    # no extra args needed for non-cross builds
    "//conditions:default": [],
}) + [
    "-g",
    "-O3",  # force -O3 even we are using --debug (for example on CI)
    "shared",
    "-DPURIFY",
    "no-threads",
    "no-tests",
    "--prefix=%s/kong" % KONG_VAR["INSTALL_DESTDIR"],
    "--openssldir=%s/kong" % KONG_VAR["INSTALL_DESTDIR"],
    "--libdir=lib",  # force lib instead of lib64 (multilib postfix)
    "-Wl,-rpath,%s/kong/lib" % KONG_VAR["INSTALL_DESTDIR"],
] + select({
    "@kong//:debug_flag": ["--debug"],
    "//conditions:default": [],
})

def build_openssl(
        name = "openssl"):
    extra_make_targets = []
    extra_configure_options = []

    native.filegroup(
        name = name + "-all_srcs",
        srcs = native.glob(
            include = ["**"],
            exclude = ["*.bazel"],
        ),
    )

    configure_make(
        name = name,
        configure_command = "config",
        configure_in_place = True,
        configure_options = CONFIGURE_OPTIONS + extra_configure_options,
        env = select({
            "@platforms//os:macos": {
                "AR": "/usr/bin/ar",
            },
            "//conditions:default": {},
        }),
        lib_source = ":%s-all_srcs" % name,
        # Note that for Linux builds, libssl must come before libcrypto on the linker command-line.
        # As such, libssl must be listed before libcrypto
        out_shared_libs = select({
            "@platforms//os:macos": [
                "libssl.3.dylib",
                "libcrypto.3.dylib",
                "ossl-modules/legacy.dylib",
                "engines-3/capi.dylib",
                "engines-3/loader_attic.dylib",
                "engines-3/padlock.dylib",
            ],
            "//conditions:default": [
                "libssl.so.3",
                "libcrypto.so.3",
                "ossl-modules/legacy.so",
                "engines-3/afalg.so",
                "engines-3/capi.so",
                "engines-3/loader_attic.so",
                "engines-3/padlock.so",
            ],
        }),
        out_include_dir = "include/openssl",
        targets = [
            "-j" + KONG_VAR["NPROC"],
            # don't set the prefix by --prefix switch, but only override the install destdir using INSTALLTOP
            # while install. this makes both bazel and openssl (build time generated) paths happy.
            "install_sw INSTALLTOP=$BUILD_TMPDIR/$INSTALL_PREFIX",
        ] + extra_make_targets,
        # TODO: uncomment this to allow bazel build a perl if not installed on system
        # toolchains = ["@rules_perl//:current_toolchain"],
        visibility = ["//visibility:public"],
    )
