"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def libxcrypt_repositories():
    """Defines the libcrypt repository"""

    # many distros starts replace glibc/libcrypt with libxcrypt
    # thus crypt.h and libcrypt.so.1 are missing from cross tool chain
    # ubuntu2004: 4.4.10
    # ubuntu2204: 4.4.27
    # ubuntu2204: 4.4.36
    http_archive(
        name = "cross_deps_libxcrypt",
        url = "https://github.com/besser82/libxcrypt/releases/download/v4.4.36/libxcrypt-4.4.36.tar.xz",
        sha256 = "e5e1f4caee0a01de2aee26e3138807d6d3ca2b8e67287966d1fefd65e1fd8943",
        strip_prefix = "libxcrypt-4.4.36",
        build_file = "//build/cross_deps/libxcrypt:BUILD.libxcrypt.bazel",
    )
