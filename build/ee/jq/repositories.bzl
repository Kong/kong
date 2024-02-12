"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def jq_repositories():
    """Defines the jq repository"""

    version = KONG_VAR["LIBJQ"]

    maybe(
        http_archive,
        name = "jq",
        url = "https://github.com/jqlang/jq/releases/download/jq-" + version + "/jq-" + version + ".tar.gz",
        sha256 = "478c9ca129fd2e3443fe27314b455e211e0d8c60bc8ff7df703873deeee580c2",
        strip_prefix = "jq-" + version,
        build_file = "//build/ee/jq:BUILD.jq.bazel",
    )