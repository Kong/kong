"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def libxcrypt_repositories():
    """Defines the libcrypt repository"""

    # many distros starts replace glibc/libcrypt with libxcrypt
    # thus crypt.h and libcrypt.so.1 are missing from cross tool chain
    # ubuntu2004: 4.4.10
    # ubuntu2204: 4.4.27
    # ubuntu2404: 4.4.36
    # NOTE: do not bump the following version, see build/cross_deps/README.md for detail.
    http_archive(
        name = "cross_deps_libxcrypt",
        url = "https://github.com/besser82/libxcrypt/releases/download/v4.4.27/libxcrypt-4.4.27.tar.xz",
        sha256 = "500898e80dc0d027ddaadb5637fa2bf1baffb9ccd73cd3ab51d92ef5b8a1f420",
        strip_prefix = "libxcrypt-4.4.27",
        build_file = "//build/cross_deps/libxcrypt:BUILD.libxcrypt.bazel",
        patches = ["//build/cross_deps/libxcrypt:001-4.4.27-enable-hash-all.patch"],
        patch_args = ["-p1"],
    )
