"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def passwdqc_repositories():
    """Defines the passwdqc repository"""

    version = KONG_VAR["PASSWDQC"]

    maybe(
        http_archive,
        name = "passwdqc",
        url = "https://www.openwall.com/passwdqc/passwdqc-" + version + ".tar.gz",
        sha256 = KONG_VAR["PASSWDQC_SHA256"],
        strip_prefix = "passwdqc-" + version,
        build_file = "//build/ee/passwdqc:BUILD.passwdqc.bazel",
        patches = ["//build/ee/passwdqc:passwdqc-cross.patch"],
    )
