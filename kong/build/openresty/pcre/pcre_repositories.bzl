"""A module defining the third party dependency PCRE"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def pcre_repositories():
    version = KONG_VAR["PCRE"]

    maybe(
        http_archive,
        name = "pcre",
        build_file = "//build/openresty/pcre:BUILD.pcre.bazel",
        strip_prefix = "pcre2-" + version,
        sha256 = KONG_VAR["PCRE_SHA256"],
        urls = [
            "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-" + version + "/pcre2-" + version + ".tar.gz",
        ],
    )
