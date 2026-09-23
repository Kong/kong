"""A module defining the third party dependency LUA"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

def lua_repositories():
    maybe(
        http_archive,
        name = "lua",
        build_file = "//build/luarocks/lua:BUILD.lua.bazel",
        strip_prefix = "lua-5.1.5",
        sha256 = "2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333",
        urls = [
            "https://www.lua.org/ftp/lua-5.1.5.tar.gz",
        ],
        patches = ["//build/luarocks/lua:patches/lua-cross.patch"],
        patch_args = ["-p1"],
    )
