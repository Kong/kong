"""A module defining the third party dependency msgpack-c"""

load("@bazel_tools//tools/build_defs/repo:git.bzl", "new_git_repository")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def msgpack_c_repositories():
    maybe(
        new_git_repository,
        name = "msgpack_c",
        branch = KONG_VAR["LUAJIT_DEP_MSGPACK_C_VERSION"],
        remote = "https://github.com/msgpack/msgpack-c",
        visibility = ["//visibility:public"],  # let this to be referenced by openresty build
        build_file = "//build/openresty/msgpack_c:BUILD.msgpack_c.bazel",
    )
