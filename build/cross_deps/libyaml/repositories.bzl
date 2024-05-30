"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def libyaml_repositories():
    """Defines the libyaml repository"""

    version = KONG_VAR["LIBYAML"]

    http_archive(
        name = "cross_deps_libyaml",
        url = "https://pyyaml.org/download/libyaml/yaml-" + version + ".tar.gz",
        sha256 = KONG_VAR["LIBYAML_SHA256"],
        strip_prefix = "yaml-" + version,
        build_file = "//build/cross_deps/libyaml:BUILD.libyaml.bazel",
    )
