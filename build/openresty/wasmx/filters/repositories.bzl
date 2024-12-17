load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("//build:build_system.bzl", "github_release")
load(":variables.bzl", "WASM_FILTERS")

def wasm_filters_repositories():
    for filter in WASM_FILTERS:
        for file in filter["files"].keys():
            maybe(
                github_release,
                name = "%s-%s" % (filter["name"], file),
                repo = filter["repo"],
                tag = filter["tag"],
                pattern = file,
                extract = False,
                skip_add_copyright_header = True,
                sha256 = filter["files"][file],
            )
