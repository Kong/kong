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
        url = "https://github.com/Kong/crosstool-ng-actions/releases/download/0.8.0/aarch64-rhel9-linux-gnu-glibc-2.34-gcc-11.tar.gz",
        sha256 = "b8f9573cb71d5556aea5a0e13c205786b5817f54273e2efcde71548e9eb297a2",
        strip_prefix = "aarch64-rhel9-linux-gnu",
        build_file_content = build_file_content,
    )

    http_archive(
        name = "aarch64-rhel8-linux-gnu-gcc-8",
        url = "https://github.com/Kong/crosstool-ng-actions/releases/download/0.8.0/aarch64-rhel8-linux-gnu-glibc-2.28-gcc-8.tar.gz",
        sha256 = "f802d09c54f037f78198ff90bf847d822529ec3c6797a922e282453ad44321ef",
        strip_prefix = "aarch64-rhel8-linux-gnu",
        build_file_content = build_file_content,
    )

    http_archive(
        name = "aarch64-aws2023-linux-gnu-gcc-11",
        url = "https://github.com/Kong/crosstool-ng-actions/releases/download/0.8.0/aarch64-aws2023-linux-gnu-glibc-2.34-gcc-11.tar.gz",
        sha256 = "4b5ef1511035fcb4b95c543485dc7a72675abcb27c4d2b6a20ac4598f2717a9f",
        strip_prefix = "aarch64-aws2023-linux-gnu",
        build_file_content = build_file_content,
    )

    http_archive(
        name = "aarch64-aws2-linux-gnu-gcc-8",
        url = "https://github.com/Kong/crosstool-ng-actions/releases/download/0.8.0/aarch64-aws2-linux-gnu-glibc-2.26-gcc-8.tar.gz",
        sha256 = "4bcf3e5448cca6c33f8d6d3e97da0378cfa57b116e5ba6f037e4fd11149ed37f",
        strip_prefix = "aarch64-aws2-linux-gnu",
        build_file_content = build_file_content,
    )

    http_archive(
        name = "x86_64-aws2-linux-gnu-gcc-8",
        url = "https://github.com/Kong/crosstool-ng-actions/releases/download/0.8.0/x86_64-aws2-linux-gnu-glibc-2.26-gcc-8.tar.gz",
        sha256 = "bb742616c651900280ac63e926d941fa4bb851e648d011a04a29de62e818e516",
        strip_prefix = "x86_64-aws2-linux-gnu",
        build_file_content = build_file_content,
    )
