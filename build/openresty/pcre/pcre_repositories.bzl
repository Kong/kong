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
        sha256 = "c33b418e3b936ee3153de2c61cc638e7e4fe3156022a5c77d0711bcbb9d64f1f",
        urls = [
            "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-" + version + "/pcre2-" + version + ".tar.gz",
        ],
    )
