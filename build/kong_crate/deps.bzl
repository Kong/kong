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

    # To get the sha256s, please check out the
    # https://static.rust-lang.org/dist/channel-rust-stable.toml
    rust_register_toolchains(
        edition = "2021",
        extra_target_triples = ["aarch64-unknown-linux-gnu"],
        sha256s = {
            "rustc-1.82.0-x86_64-unknown-linux-gnu.tar.xz": "90b61494f5ccfd4d1ca9a5ce4a0af49a253ca435c701d9c44e3e44b5faf70cb8",
            "clippy-1.82.0-x86_64-unknown-linux-gnu.tar.xz": "ea4fbf6fbd3686d4f6e2a77953e2d42a86ea31e49a5f79ec038762c413b15577",
            "cargo-1.82.0-x86_64-unknown-linux-gnu.tar.xz": "97aeae783874a932c4500f4d36473297945edf6294d63871784217d608718e70",
            "llvm-tools-1.82.0-x86_64-unknown-linux-gnu.tar.xz": "29f9becd0e5f83196f94779e9e06ab76e0bd3a14bcdf599fabedbd4a69d045be",
            "rust-std-1.82.0-x86_64-unknown-linux-gnu.tar.xz": "2eca3d36f7928f877c334909f35fe202fbcecce109ccf3b439284c2cb7849594",
        },
        versions = ["1.82.0"],
    )

    rust_repository_set(
        name = "rust_linux_arm64_linux_tuple",
        edition = "2021",
        exec_triple = "x86_64-unknown-linux-gnu",
        extra_target_triples = ["aarch64-unknown-linux-gnu"],
        sha256s = {
            "rustc-1.82.0-aarch64-unknown-linux-gnu.tar.xz": "2958e667202819f6ba1ea88a2a36d7b6a49aad7e460b79ebbb5cf9221b96f599",
            "clippy-1.82.0-aarch64-unknown-linux-gnu.tar.xz": "1e01808028b67a49f57925ea72b8a2155fbec346cd694d951577c63312ba9217",
            "cargo-1.82.0-aarch64-unknown-linux-gnu.tar.xz": "05c0d904a82cddb8a00b0bbdd276ad7e24dea62a7b6c380413ab1e5a4ed70a56",
            "llvm-tools-1.82.0-aarch64-unknown-linux-gnu.tar.xz": "db793edd8e8faef3c9f2aa873546c6d56b3421b2922ac9111ba30190b45c3b5c",
            "rust-std-1.82.0-aarch64-unknown-linux-gnu.tar.xz": "1359ac1f3a123ae5da0ee9e47b98bb9e799578eefd9f347ff9bafd57a1d74a7f",
        },
        versions = ["1.82.0"],
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

    crates_repository(
        name = "resty_ja4_crate_index",
        cargo_lockfile = "//:crate_locks/resty_ja4.Cargo.lock",
        isolated = cargo_home_isolated,
        lockfile = "//:crate_locks/resty_ja4.lock",
        manifests = [
            "@resty_ja4//:Cargo.toml",
        ],
    )
