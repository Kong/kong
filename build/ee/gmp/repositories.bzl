"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def gmp_repositories():
    """Defines the gmp repository"""

    version = KONG_VAR["KONG_GMP_VERSION"]

    maybe(
        http_archive,
        name = "gmp",
        url = "https://ftp.gnu.org/gnu/gmp/gmp-" + version + ".tar.bz2",
        sha256 = "eae9326beb4158c386e39a356818031bd28f3124cf915f8c5b1dc4c7a36b4d7c",
        strip_prefix = "gmp-" + version,
        build_file = "//build/ee/gmp:BUILD.gmp.bazel",
    )
