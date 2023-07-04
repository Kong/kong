"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def libxslt_repositories():
    """Defines the libxslt repository"""

    version = KONG_VAR["LIBXSLT"]
    version_major_minor = ".".join(KONG_VAR["LIBXSLT"].split(".")[:2])

    maybe(
        http_archive,
        name = "libxslt",
        urls = [
            "https://download.gnome.org/sources/libxslt/" + version_major_minor + "/libxslt-" + version + ".tar.xz",
            "https://ftp.osuosl.org/pub/blfs/conglomeration/libxslt/" + "/libxslt-" + version + ".tar.xz",
        ],
        sha256 = "3a4b27dc8027ccd6146725950336f1ec520928f320f144eb5fa7990ae6123ab4",
        strip_prefix = "libxslt-" + version,
        build_file = "//build/ee/libxslt:BUILD.libxslt.bazel",
    )
