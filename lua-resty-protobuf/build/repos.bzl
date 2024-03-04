"""Setup repostories."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def resty_protobuf_repositories():
    http_archive(
        name = "bazel_skylib",
        sha256 = "cd55a062e763b9349921f0f5db8c3933288dc8ba4f76dd9416aac68acee3cb94",
        urls = [
            "https://mirror.bazel.build/github.com/bazelbuild/bazel-skylib/releases/download/1.5.0/bazel-skylib-1.5.0.tar.gz",
            "https://github.com/bazelbuild/bazel-skylib/releases/download/1.5.0/bazel-skylib-1.5.0.tar.gz",
        ],
    )

    http_archive(
        name = "rules_rust",
        integrity = "sha256-ZQGWDD5NoySV0eEAfe0HaaU0yxlcMN6jaqVPnYo/A2E=",
        urls = ["https://github.com/bazelbuild/rules_rust/releases/download/0.38.0/rules_rust-v0.38.0.tar.gz"],
    )
