"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

musl_build_file_content = """
filegroup(
    name = "toolchain",
    srcs = glob(
        include = [
            "bin/**",
            "include/**",
            "lib/**",
            "libexec/**",
            "share/**",
            "*-linux-musl/**",
        ],
        exclude = ["usr"],
    ),
    visibility = ["//visibility:public"],
)
"""

def toolchain_repositories():
    http_archive(
        name = "x86_64-alpine-linux-musl-gcc-11",
        url = "https://github.com/Kong/crosstool-ng-actions/releases/download/0.4.0/x86_64-alpine-linux-musl-gcc-11.tar.gz",
        sha256 = "4fbc9a48f1f7ace6d2a19a1feeac1f69cf86ce8ece40b101e351d1f703b3560c",
        strip_prefix = "x86_64-alpine-linux-musl",
        build_file_content = musl_build_file_content,
    )

    http_archive(
        name = "aarch64-alpine-linux-musl-gcc-11",
        url = "https://github.com/Kong/crosstool-ng-actions/releases/download/0.4.0/aarch64-alpine-linux-musl-gcc-11.tar.gz",
        sha256 = "abd7003fc4aa6d533c5aad97a5726040137f580026b1db78d3a8059a69c3d45b",
        strip_prefix = "aarch64-alpine-linux-musl",
        build_file_content = musl_build_file_content,
    )
