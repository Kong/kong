"""A module defining the dependency atc-router"""

load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def atc_router_repositories():
    maybe(
        git_repository,
        name = "atc_router",
        branch = KONG_VAR["ATC_ROUTER"],
        remote = "https://github.com/Kong/atc-router",
        visibility = ["//visibility:public"],  # let this to be referenced by openresty build
    )
