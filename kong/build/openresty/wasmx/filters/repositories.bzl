load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load(":variables.bzl", "WASM_FILTERS")

def wasm_filters_repositories():
    for filter in WASM_FILTERS:
        for file in filter["files"].keys():
            maybe(
                http_file,
                name = "%s-%s" % (filter["name"], file),
                downloaded_file_path = file,
                url = "https://github.com/%s/releases/download/%s/%s" % (
                    filter["repo"],
                    filter["tag"],
                    file,
                ),
                sha256 = filter["files"][file],
            )
