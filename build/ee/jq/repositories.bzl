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
        sha256 = "402a0d6975d946e6f4e484d1a84320414a0ff8eb6cf49d2c11d144d4d344db62",
        strip_prefix = "jq-" + version,
        build_file = "//build/ee/jq:BUILD.jq.bazel",
    )
