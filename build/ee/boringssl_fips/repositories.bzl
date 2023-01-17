"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def boringssl_fips_repositories():
    """Defines the boringssl repository"""

    version = KONG_VAR["RESTY_BORINGSSL_VERSION"]

    maybe(
        http_archive,
        name = "boringssl_fips",
        sha256 = "3b5fdf23274d4179c2077b5e8fa625d9debd7a390aac1d165b7e47234f648bb8",
        urls = ["https://commondatastorage.googleapis.com/chromium-boringssl-fips/boringssl-" + version + ".tar.xz"],
        strip_prefix = "boringssl",
        patches = ["//build/ee/boringssl_fips:boringssl_fips.patch"],
        patch_args = ["-p1"],
        build_file = "//build/ee/boringssl_fips:BUILD.bazel",
    )
