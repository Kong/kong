"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def zlib_repositories():
    """Defines the zlib repository"""

    http_archive(
        name = "cross_deps_zlib",
        urls = [
            "https://zlib.net/zlib-1.2.13.tar.gz",
            "https://zlib.net/fossils/zlib-1.2.13.tar.gz",
        ],
        sha256 = "b3a24de97a8fdbc835b9833169501030b8977031bcb54b3b3ac13740f846ab30",
        strip_prefix = "zlib-1.2.13",
        build_file = "//build/cross_deps/zlib:BUILD.zlib.bazel",
    )
