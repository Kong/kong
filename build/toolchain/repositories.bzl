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
        name = "aarch64-rhel9-linux-gnu-gcc-11",
        url = "https://github.com/Kong/crosstool-ng-actions/releases/download/0.8.2/aarch64-rhel9-linux-gnu-glibc-2.34-gcc-11.tar.gz",
        sha256 = "bcf38c5221fe96978428e8a7e0255cb8285008378f627dad8ad5a219adf99493",
        strip_prefix = "aarch64-rhel9-linux-gnu",
        build_file_content = build_file_content,
    )

    http_archive(
        name = "aarch64-rhel8-linux-gnu-gcc-8",
        url = "https://github.com/Kong/crosstool-ng-actions/releases/download/0.8.2/aarch64-rhel8-linux-gnu-glibc-2.28-gcc-8.tar.gz",
        sha256 = "44068f3c1ef59a9f1049c25c975c5180968321dea4f7333f640176abac95bc88",
        strip_prefix = "aarch64-rhel8-linux-gnu",
        build_file_content = build_file_content,
    )

    http_archive(
        name = "aarch64-aws2023-linux-gnu-gcc-11",
        url = "https://github.com/Kong/crosstool-ng-actions/releases/download/0.8.2/aarch64-aws2023-linux-gnu-glibc-2.34-gcc-11.tar.gz",
        sha256 = "3d3cfa475052f841304e3a0d7943827f2a9e4fa0dacafbfb0aaa95921d682459",
        strip_prefix = "aarch64-aws2023-linux-gnu",
        build_file_content = build_file_content,
    )
