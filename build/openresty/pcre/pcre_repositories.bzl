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
        sha256 = "889d16be5abb8d05400b33c25e151638b8d4bac0e2d9c76e9d6923118ae8a34e",
        urls = [
            "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-" + version + "/pcre2-" + version + ".tar.gz",
        ],
    )
