"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def libexpat_repositories():
    """Defines the libexpat repository"""

    version = KONG_VAR["KONG_DEP_EXPAT_VERSION"]
    tag = "R_" + version.replace(".", "_")

    maybe(
        http_archive,
        name = "libexpat",
        url = "https://github.com/libexpat/libexpat/releases/download/" + tag + "/expat-" + version + ".tar.gz",
        sha256 = "4415710268555b32c4e5ab06a583bea9fec8ff89333b218b70b43d4ca10e38fa",
        strip_prefix = "expat-" + version,
        build_file = "//build/ee/libexpat:BUILD.libexpat.bazel",
    )
