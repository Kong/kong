"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def passwdqc_repositories():
    """Defines the passedqc repository"""

    version = KONG_VAR["PASSWDQC"]

    maybe(
        http_archive,
        name = "passwdqc",
        url = "https://github.com/openwall/passwdqc/archive/refs/tags/PASSWDQC_" + version + ".tar.gz",
        sha256 = "f07bdc16708652f54170f7d2bff03f4f53456b0db52893866bfef9a0e16deeed",
        strip_prefix = "passwdqc-PASSWDQC_" + version,
        build_file = "//build/ee/passwdqc:BUILD.passwdqc.bazel",
        patches = ["//build/ee/passwdqc:passwdqc-cross.patch"],
    )
