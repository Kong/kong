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
        sha256 = "56ab9b90f5acbc42eb7a94cf482e6c058a63e8a1effdf572b8b2a6323a06d923",
        urls = [
            "https://luarocks.org/releases/luarocks-" + version + ".tar.gz",
        ],
    )
