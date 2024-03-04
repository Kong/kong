load("@rules_rust//rust:defs.bzl", "rust_shared_library")
load("@resty_protobuf_crate_index//:defs.bzl", "aliases", "all_crate_deps")

filegroup(
    name = "all_srcs",
    srcs = glob(
        include = [
            "src/**",
            "Cargo.toml",
            "Cargo.lock",
        ],
        exclude = [
            "*.bazel",
        ],
    ),
)

rust_shared_library(
    name = "resty_protobuf",
    srcs = [":all_srcs"],
    aliases = aliases(),
    rustc_flags = [
        "--codegen=strip=symbols",
    ],
    crate_features = [
        "default",
        "ffi",
    ],
    proc_macro_deps = all_crate_deps(
        proc_macro = True,
    ),
    visibility = ["//visibility:public"],
    deps = all_crate_deps(
        normal = True,
    ),
)
