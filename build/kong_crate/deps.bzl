"""Setup dependencies after repostories are downloaded."""

load("@rules_rust//crate_universe:defs.bzl", "crates_repository")
load("@rules_rust//crate_universe:repositories.bzl", "crate_universe_dependencies")
load("@rules_rust//rust:repositories.bzl", "rules_rust_dependencies", "rust_register_toolchains", "rust_repository_set")

def kong_crate_repositories(cargo_lockfile, lockfile, cargo_home_isolated = True):
    """
    Setup Kong Crates repostories

    Args:
        cargo_lockfile (label): Label to the Cargo.Bazel.lock file,
        the document of the crate_universe says that this is to make sure that
        Bazel and Cargo are using the same crate versions.
        However, we just need the source of the Rust dependencies, we don't need the
        `Cargo.lock` file, but this is a mandatory argument, so we just pass the path
        to the `Cargo.Bazel.lock` file to make it happy.

        lockfile (label): Label to the Cargo.Bazel.lock.json file,
        this is the lockfile for reproducible builds.

        cargo_home_isolated (bool): `False` to reuse system CARGO_HOME
        for faster builds. `True` is default and will use isolated
        Cargo home, which takes about 2 minutes to bootstrap.
    """

    rules_rust_dependencies()

    rust_register_toolchains(
        edition = "2021",
        extra_target_triples = ["aarch64-unknown-linux-gnu"],
    )

    rust_repository_set(
        name = "rust_linux_arm64_linux_tuple",
        edition = "2021",
        exec_triple = "x86_64-unknown-linux-gnu",
        extra_target_triples = ["aarch64-unknown-linux-gnu"],
        versions = ["stable"],
    )

    crate_universe_dependencies()

    crates_repository(
        name = "kong_crate_index",
        cargo_lockfile = cargo_lockfile,
        isolated = cargo_home_isolated,
        lockfile = lockfile,
        manifests = [
            "@atc_router//:Cargo.toml",
        ],
    )
