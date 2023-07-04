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
        sha256 = "5d2cc3d78bec3dbe212a9d7fa629ada25a7da928af432c93060ff5c17ee28a9c",
        strip_prefix = "libxml2-" + version,
        build_file = "//build/ee/libxml2:BUILD.libxml2.bazel",
    )
