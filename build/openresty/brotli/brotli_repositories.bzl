"""A module defining the dependency """

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@kong_bindings//:variables.bzl", "KONG_VAR")
load("//build:build_system.bzl", "git_or_local_repository")

def brotli_repositories():
    maybe(
        git_or_local_repository,
        name = "brotli",
        branch = KONG_VAR["BROTLI"],
        remote = "https://github.com/google/brotli",
    )
