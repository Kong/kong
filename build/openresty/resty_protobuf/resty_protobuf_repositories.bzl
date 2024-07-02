"""A module defining the dependency atc-router"""

# load("@bazel_tools//tools/build_defs/repo:local.bzl", "local_repository")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
# load("@kong_bindings//:variables.bzl", "KONG_VAR")

def resty_protobuf_repositories():
    maybe(
        native.local_repository,
        name = "resty_protobuf",
        path = "lua-resty-protobuf",
        # visibility = ["//visibility:public"],  # let this to be referenced by openresty build
    )
