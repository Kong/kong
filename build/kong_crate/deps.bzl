"""Setup dependencies after repostories are downloaded."""

load("@rules_rust//crate_universe:defs.bzl", "crates_repository")
load("@rules_rust//crate_universe:repositories.bzl", "crate_universe_dependencies")
load("@rules_rust//rust:repositories.bzl", "rules_rust_dependencies", "rust_register_toolchains", "rust_repository_set")

def kong_crate_repositories(cargo_home_isolated = True):
    """
    Setup Kong Crates repostories

    Args:
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
        name = "atc_router_crate_index",
        cargo_lockfile = "//:crate_locks/atc_router.Cargo.lock",
        isolated = cargo_home_isolated,
        lockfile = "//:crate_locks/atc_router.lock",
        manifests = [
            "@atc_router//:Cargo.toml",
        ],
    )

    crates_repository(
        name = "json_threat_protection_crate_index",
        cargo_lockfile = "//:crate_locks/json_threat_protection.Cargo.lock",
        isolated = cargo_home_isolated,
        lockfile = "//:crate_locks/json_threat_protection.lock",
        manifests = [
            "@json_threat_protection//:Cargo.toml",
        ],
    )

    crates_repository(
        name = "jsonschema_crate_index",
        cargo_lockfile = "//:crate_locks/jsonschema.Cargo.lock",
        isolated = cargo_home_isolated,
        lockfile = "//:crate_locks/jsonschema.lock",
        manifests = [
            "@jsonschema//:Cargo.toml",
        ],
    )
