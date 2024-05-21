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
        url = "https://github.com/Kong/crosstool-ng-actions/releases/download/0.7.0/aarch64-rhel9-linux-gnu-glibc-2.34-gcc-11.tar.gz",
        sha256 = "8db520adb98f43dfe3da5d51e09679b85956e3a11362d7cba37a85065e87fcf7",
        strip_prefix = "aarch64-rhel9-linux-gnu",
        build_file_content = build_file_content,
    )

    http_archive(
        name = "aarch64-rhel8-linux-gnu-gcc-8",
        url = "https://github.com/Kong/crosstool-ng-actions/releases/download/0.7.0/aarch64-rhel8-linux-gnu-glibc-2.28-gcc-8.tar.gz",
        sha256 = "de41ca31b6a056bddd770b4cb50fe8e8c31e8faa9ce857771ab7410a954d1cbe",
        strip_prefix = "aarch64-rhel8-linux-gnu",
        build_file_content = build_file_content,
    )

    http_archive(
        name = "aarch64-aws2023-linux-gnu-gcc-11",
        url = "https://github.com/Kong/crosstool-ng-actions/releases/download/0.7.0/aarch64-aws2023-linux-gnu-glibc-2.34-gcc-11.tar.gz",
        sha256 = "c0333ba0934b32f59ab9c3076c47785c94413aae264cc2ee78d6d5fd46171a9d",
        strip_prefix = "aarch64-aws2023-linux-gnu",
        build_file_content = build_file_content,
    )

    http_archive(
        name = "aarch64-aws2-linux-gnu-gcc-7",
        url = "https://github.com/Kong/crosstool-ng-actions/releases/download/0.7.0/aarch64-aws2-linux-gnu-glibc-2.26-gcc-7.tar.gz",
        sha256 = "de365a366b5de93b0f6d851746e7ced06946b083b390500d4c1b4a8360702331",
        strip_prefix = "aarch64-aws2-linux-gnu",
        build_file_content = build_file_content,
    )

    http_archive(
        name = "x86_64-aws2-linux-gnu-gcc-7",
        url = "https://github.com/Kong/crosstool-ng-actions/releases/download/0.7.0/x86_64-aws2-linux-gnu-glibc-2.26-gcc-7.tar.gz",
        sha256 = "645c242d13bf456ca59a7e9701e9d2f53336fd0497ccaff2b151da9921469985",
        strip_prefix = "x86_64-aws2-linux-gnu",
        build_file_content = build_file_content,
    )
