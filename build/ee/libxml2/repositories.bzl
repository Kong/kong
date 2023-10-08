"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def libxml2_repositories():
    """Defines the libxml2 repository"""

    version = KONG_VAR["LIBXML2"]
    version_major_minor = ".".join(KONG_VAR["LIBXML2"].split(".")[:2])

    maybe(
        http_archive,
        name = "libxml2",
        urls = [
            "https://download.gnome.org/sources/libxml2/" + version_major_minor + "/libxml2-" + version + ".tar.xz",
            "https://ftp.osuosl.org/pub/blfs/conglomeration/libxml2/" + "/libxml2-" + version + ".tar.xz",
        ],
        sha256 = "3727b078c360ec69fa869de14bd6f75d7ee8d36987b071e6928d4720a28df3a6",
        strip_prefix = "libxml2-" + version,
        build_file = "//build/ee/libxml2:BUILD.libxml2.bazel",
    )
