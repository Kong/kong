"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def passwdqc_repositories():
    """Defines the passedqc repository"""

    version = KONG_VAR["KONG_DEP_PASSWDQC_VERSION"]

    maybe(
        http_archive,
        name = "passwdqc",
        url = "https://www.openwall.com/passwdqc/passwdqc-" + version + ".tar.gz",
        sha256 = "d1fedeaf759e8a0f32d28b5811ef11b5a5365154849190f4b7fab670a70ffb14",
        strip_prefix = "passwdqc-" + version,
        build_file = "//build/ee/passwdqc:BUILD.passwdqc.bazel",
        patches = ["//build/ee/passwdqc:passwdqc-cross.patch"],
    )
