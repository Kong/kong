"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def libxcrypt_repositories():
    """Defines the libcrypt repository"""

    version = KONG_VAR["LIBXCRYPT"]

    # many distros starts replace glibc/libcrypt with libxcrypt
    # thus crypt.h and libcrypt.so.1 are missing from cross tool chain
    # ubuntu2004: 4.4.10
    # ubuntu2204: 4.4.27
    http_archive(
        name = "cross_deps_libxcrypt",
        url = "https://github.com/besser82/libxcrypt/releases/download/v" + version + "/libxcrypt-" + version + ".tar.xz",
        sha256 = KONG_VAR["LIBXCRYPT_SHA256"],
        strip_prefix = "libxcrypt-" + version,
        build_file = "//build/cross_deps/libxcrypt:BUILD.libxcrypt.bazel",
    )
