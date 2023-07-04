"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def libexpat_repositories():
    """Defines the libexpat repository"""

    version = KONG_VAR["LIBEXPAT"]
    tag = "R_" + version.replace(".", "_")

    maybe(
        http_archive,
        name = "libexpat",
        url = "https://github.com/libexpat/libexpat/releases/download/" + tag + "/expat-" + version + ".tar.gz",
        sha256 = "6b902ab103843592be5e99504f846ec109c1abb692e85347587f237a4ffa1033",
        strip_prefix = "expat-" + version,
        build_file = "//build/ee/libexpat:BUILD.libexpat.bazel",
    )
