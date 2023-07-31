"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

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
            "*-linux-*/**",
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
        build_file_content = build_file_content,
    )

    http_archive(
        name = "aarch64-alpine-linux-musl-gcc-11",
        url = "https://github.com/Kong/crosstool-ng-actions/releases/download/0.4.0/aarch64-alpine-linux-musl-gcc-11.tar.gz",
        sha256 = "abd7003fc4aa6d533c5aad97a5726040137f580026b1db78d3a8059a69c3d45b",
        strip_prefix = "aarch64-alpine-linux-musl",
        build_file_content = build_file_content,
    )

    http_archive(
        name = "aarch64-rhel9-linux-gnu-gcc-11",
        url = "https://github.com/Kong/crosstool-ng-actions/releases/download/0.5.0/aarch64-rhel9-linux-gnu-glibc-2.34-gcc-11.tar.gz",
        sha256 = "40fcf85e8315869621573512499aa3e2884283e0054dfefc2bad3bbf21b954c0",
        strip_prefix = "aarch64-rhel9-linux-gnu",
        build_file_content = build_file_content,
    )

    http_archive(
        name = "aarch64-rhel8-linux-gnu-gcc-8",
        url = "https://github.com/Kong/crosstool-ng-actions/releases/download/0.5.0/aarch64-rhel8-linux-gnu-glibc-2.28-gcc-8.tar.gz",
        sha256 = "7a9a28ccab6d3b068ad49b2618276707e0a31b437ad010c8969ba8660ddf63fb",
        strip_prefix = "aarch64-rhel8-linux-gnu",
        build_file_content = build_file_content,
    )

    http_archive(
        name = "aarch64-aws2023-linux-gnu-gcc-11",
        url = "https://github.com/Kong/crosstool-ng-actions/releases/download/0.5.0/aarch64-aws2023-linux-gnu-glibc-2.34-gcc-11.tar.gz",
        sha256 = "01498b49c20255dd3d5da733fa5d60b5dad4b1cdd55e50552d8f2867f3d82e98",
        strip_prefix = "aarch64-aws2023-linux-gnu",
        build_file_content = build_file_content,
    )

    http_archive(
        name = "aarch64-aws2-linux-gnu-gcc-7",
        url = "https://github.com/Kong/crosstool-ng-actions/releases/download/0.5.0/aarch64-aws2-linux-gnu-glibc-2.26-gcc-7.tar.gz",
        sha256 = "9a8d0bb84c3eea7b662192bf44aaf33a76c9c68848a68a544a91ab90cd8cba60",
        strip_prefix = "aarch64-aws2-linux-gnu",
        build_file_content = build_file_content,
    )
