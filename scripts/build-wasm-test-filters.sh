#!/bin/bash

# Build the WASM filters used by our integration tests.
#
# Much of this work is duplicated by a composite GitHub Action which lives
# here:
#   .github/actions/build-wasm-test-filters/action.yml
#
# The GitHub Action is the prettier, more maintainable install process used
# by CI. This script is for local development, so that engineers can just
# run `make dev` and have everything work.
#
# By default, all installed/built assets are placed under the bazel build
# directory. This is to ensure that everything can be cleaned up easily.
#
# Currently, these are all written in Rust, so we just have to worry about
# ensuring that the Rust toolchain is present before building with cargo.


set -euo pipefail

readonly BUILD_TARGET=wasm32-wasi
readonly FIXTURE_PATH=${PWD}/spec/fixtures/proxy_wasm_filters

readonly INSTALL_ROOT=${PWD}/bazel-bin/build/${BUILD_NAME:-kong-dev}
readonly TARGET_DIR=${INSTALL_ROOT}/wasm-cargo-target

readonly KONG_TEST_USER_CARGO_DISABLED=${KONG_TEST_USER_CARGO_DISABLED:-0}
readonly KONG_TEST_CARGO_BUILD_MODE=${KONG_TEST_CARGO_BUILD_MODE:-debug}
readonly KONG_TEST_WASM_FILTERS_PATH=${TARGET_DIR}/${BUILD_TARGET}/${KONG_TEST_CARGO_BUILD_MODE}


install-toolchain() {
    if [[ ! -e $INSTALL_ROOT ]]; then
        echo "ERROR: bazel install root not found ($TARGET_DIR)"
        echo
        echo "You must run bazel before running this script."
        exit 1
    fi

    export RUSTUP_HOME=$INSTALL_ROOT/rustup
    export CARGO_HOME=$INSTALL_ROOT/cargo

    mkdir -p "$RUSTUP_HOME" "$CARGO_HOME"

    export RUSTUP_INIT_SKIP_PATH_CHECK=yes

    curl \
        --proto '=https' \
        --tlsv1.2 \
        -sSf \
        https://sh.rustup.rs \
    | sh -s -- \
        -y \
        --no-modify-path \
        --profile minimal \
        --component cargo \
        --target "$BUILD_TARGET"

    export PATH=${CARGO_HOME}/bin:${PATH}
}


main() {
    if [[ -n ${CI:-} ]]; then
        echo "Skipping build-wasm-test-filters in CI"
        return 0
    fi

    cargo=$(command -v cargo || true)
    rustup=$(command -v rustup || true)

    if [[
        $KONG_TEST_USER_CARGO_DISABLED != 1 \
        && -n ${cargo:-} \
        && -n ${rustup:-} \
    ]]; then
        echo "===="
        echo "Using pre-installed rust toolchain:"
        echo "cargo => $cargo"
        echo "To disable this behavior, set KONG_TEST_USER_CARGO_DISABLED=1"
        echo "===="

        echo "Adding build target ($BUILD_TARGET)"
        rustup target add "$BUILD_TARGET"

    else
        echo "cargo not found, installing rust toolchain"

        install-toolchain

        cargo=$INSTALL_ROOT/cargo/bin/cargo

        test -x "$cargo" || {
            echo "Failed to find/install cargo"
            exit 1
        }
    fi


    "$cargo" build \
        --manifest-path "$FIXTURE_PATH/Cargo.toml" \
        --workspace \
        --lib \
        --target "$BUILD_TARGET" \
        --target-dir "$TARGET_DIR"

    test -d "$KONG_TEST_WASM_FILTERS_PATH" || {
        echo "ERROR: test filter path ($KONG_TEST_WASM_FILTERS_PATH) "
        echo "does not exist after building. This is unexpected."
        exit 1
    }

    readonly symlink="$FIXTURE_PATH/build"

    # symlink the target to a standard location used in spec/kong_tests.conf
    ln -sfv \
        "$KONG_TEST_WASM_FILTERS_PATH" \
        "$symlink"

    echo "Success! Test filters are now available at:"
    echo
    echo "$symlink"
    echo
    echo "For local development, set KONG_WASM_FILTERS_PATH accordingly:"
    echo
    echo "export KONG_WASM_FILTERS_PATH=\"$symlink\""
    echo
    echo "If testing with docker, make sure to mount the full (non-symlink) path"
    echo "inside your container:"
    echo
    echo "docker run \\"
    echo "  -e KONG_WASM_FILTERS_PATH=/filters \\"
    echo "  -v \"\$(realpath \"$symlink\"):/filters\" \\"
    echo "  ..."
}

main
