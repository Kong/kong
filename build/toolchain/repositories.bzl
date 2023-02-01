"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def toolchain_repositories():
    http_archive(
        name = "gcc-11-x86_64-linux-musl-cross",
        url = "https://more.musl.cc/11/x86_64-linux-musl/x86_64-linux-musl-cross.tgz",
        sha256 = "c6226824d6b7214ce974344b186179c9fa89be3c33dd7431c4b6585649ce840b",
        strip_prefix = "x86_64-linux-musl-cross",
        build_file_content = """
filegroup(
    name = "toolchain",
    srcs = glob(
        include = [
            "bin/**",
            "include/**",
            "lib/**",
            "libexec/**",
            "share/**",
            "x86_64-linux-musl/**",
        ],
        exclude = ["usr"],
    ),
    visibility = ["//visibility:public"],
)
        """,
    )
