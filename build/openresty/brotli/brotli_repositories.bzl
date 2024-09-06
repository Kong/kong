"""A module defining the dependency """

load("//build:build_system.bzl", "git_or_local_repository")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def brotli_repositories():
    maybe(
        git_or_local_repository,
        name = "brotli",
        branch = KONG_VAR["BROTLI"],
        remote = "https://github.com/google/brotli",
    )
