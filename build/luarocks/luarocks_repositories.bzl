"""A module defining the third party dependency luarocks"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def luarocks_repositories():
    version = KONG_VAR["LUAROCKS"]

    maybe(
        http_archive,
        name = "luarocks",
        build_file = "//build/luarocks:BUILD.luarocks.bazel",
        strip_prefix = "luarocks-" + version,
        sha256 = "bca6e4ecc02c203e070acdb5f586045d45c078896f6236eb46aa33ccd9b94edb",
        urls = [
            "https://luarocks.org/releases/luarocks-" + version + ".tar.gz",
        ],
    )
