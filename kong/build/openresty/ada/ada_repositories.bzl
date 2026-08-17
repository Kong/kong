"""A module defining the third party dependency Ada"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def ada_repositories():
    """Defines the ada repository"""

    version = KONG_VAR["ADA"]

    maybe(
        http_archive,
        name = "ada",
        sha256 = KONG_VAR["ADA_SHA256"],
        url = "https://github.com/ada-url/ada/releases/download/v" + version + "/singleheader.zip",
        type = "zip",
        build_file = "//build/openresty/ada:BUILD.bazel",
    )
