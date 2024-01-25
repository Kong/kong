"""A module defining the dependency """

load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def brotli_repositories():
    maybe(
        git_repository,
        name = "brotli",
        branch = KONG_VAR["BROTLI"],
        remote = "https://github.com/google/brotli",
        visibility = ["//visibility:public"],  # let this to be referenced by openresty build
    )
