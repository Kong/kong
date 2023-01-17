"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def jq_repositories():
    """Defines the jq repository"""

    version = KONG_VAR["KONG_DEP_LIBJQ_VERSION"]

    maybe(
        http_archive,
        name = "jq",
        url = "https://github.com/stedolan/jq/releases/download/jq-" + version + "/jq-" + version + ".tar.gz",
        sha256 = "c4d2bfec6436341113419debf479d833692cc5cdab7eb0326b5a4d4fbe9f493c",
        strip_prefix = "jq-" + version,
        build_file = "//build/ee/jq:BUILD.jq.bazel",
    )
