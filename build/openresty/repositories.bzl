"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@bazel_tools//tools/build_defs/repo:git.bzl", "new_git_repository")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def openresty_repositories():
    maybe(
        new_git_repository,
        name = "kong_build_tools",
        branch = KONG_VAR["KONG_BUILD_TOOLS_VERSION"],
        remote = "https://github.com/Kong/kong-build-tools",
        build_file = "//build/openresty:BUILD.kong-build-tools.bazel",
    )
