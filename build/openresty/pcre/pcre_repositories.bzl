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
        strip_prefix = "pcre-" + version,
        sha256 = "4e6ce03e0336e8b4a3d6c2b70b1c5e18590a5673a98186da90d4f33c23defc09",
        urls = [
            "https://mirror.bazel.build/downloads.sourceforge.net/project/pcre/pcre/" + version + "/pcre-" + version + ".tar.gz",
            "https://downloads.sourceforge.net/project/pcre/pcre/" + version + "/pcre-" + version + ".tar.gz",
        ],
    )
