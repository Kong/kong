"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def nettle_repositories():
    """Defines the nettle repository"""

    version = KONG_VAR["KONG_DEP_NETTLE_VERSION"]

    maybe(
        http_archive,
        name = "nettle",
        urls = [
            "https://ftp.gnu.org/gnu/nettle/nettle-" + version + ".tar.gz",
            "https://ftpmirror.gnu.org/gnu/nettle/nettle-" + version + ".tar.gz",
        ],
        sha256 = "661f5eb03f048a3b924c3a8ad2515d4068e40f67e774e8a26827658007e3bcf0",
        strip_prefix = "nettle-" + version,
        build_file = "//build/ee/nettle:BUILD.nettle.bazel",
    )
