"""A module defining the dependency snappy"""

load("@bazel_tools//tools/build_defs/repo:git.bzl", "new_git_repository")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def snappy_repositories():
    maybe(
        new_git_repository,
        name = "snappy",
        branch = KONG_VAR["SNAPPY"],
        remote = "https://github.com/google/snappy",
        visibility = ["//visibility:public"],  # let this to be referenced by openresty build
        build_file = "//build/openresty/snappy:BUILD.bazel",
    )
