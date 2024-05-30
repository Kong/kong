"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def zlib_repositories():
    """Defines the zlib repository"""

    version = KONG_VAR["LIBZLIB"]

    http_archive(
        name = "cross_deps_zlib",
        urls = [
            "https://zlib.net/zlib-" + version + ".tar.gz",
            "https://zlib.net/fossils/zlib-" + version + ".tar.gz",
        ],
        sha256 = KONG_VAR["LIBZLIB_SHA256"],
        strip_prefix = "zlib-" + version,
        build_file = "//build/cross_deps/zlib:BUILD.zlib.bazel",
    )
