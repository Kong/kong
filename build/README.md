# Build

This directory contains the build system for the project.
The build system is designed to be used with the [Bazel](https://bazel.build/).
It is designed to be running on Linux without root privileges, and no virtualization technology is required.

The build system is tested on Linux (Ubuntu/Debian) and macOS (M1, Ventura).

## Prerequisites

The build system requires the following tools to be installed:

- [Bazel/Bazelisk](https://bazel.build/install/bazelisk), Bazelisk is recommended to ensure the correct version of Bazel is used.
- [Build Dependencies](https://github.com/Kong/kong/blob/master/DEVELOPER.md#prerequisites), the build system requires the same dependencies as Kong itself.

## Building

To build Kong and all its dependencies, run the following command:

Bash/Zsh:

```bash
bazel build //build:kong --verbose_failures
```

The build output is in `bazel-bin/build/kong-dev`.

To use the build as a virtual development environment, run:
  
```bash
bazel build //build:venv --verbose_failures
. ./bazel-bin/build/kong-dev-venv.sh
```

Some other targets one might find useful for debugging are:

- `@openresty//:openresty`: builds openresty
- `@luarocks//:luarocks_make`: builds luarocks for Kong dependencies

### Build Options

Following build options can be used to set specific features:

- **--//:debug=true** turn on debug opitons for OpenResty and LuaJIT, default to true.
- **--action_env=BUILD_NAME=** set the `build_name`, multiple build can exist at same time to allow you
switch between different Kong versions or branches. Default to `kong-dev`; don't set this when you are
building a building an binary package.
- **--action_env=INSTALL_DESTDIR=** set the directory when the build is intended to be installed. Bazel won't
actually install files into this directory, but this will make sure certain hard coded paths and RPATH is
correctly set when building a package. Default to `bazel-bin/build/<BUILD_NAME>`.


### Official build

`--config release` specifies the build configuration to use for release, it sets following build options:

```
build:release --//:debug=false
build:release --action_env=BUILD_NAME=kong-dev
build:release --action_env=INSTALL_DESTDIR=/usr/local
```

To build an official release, use:

```bash
bazel build --config release //build:kong --verbose_failures
```

Supported build targets for binary packages:
- `:kong_deb`
- `:kong_el7`
- `:kong_el8`
- `:kong_aws2`
- `:kong_aws2022`
- `:kong_apk`

For example, to build the deb package:

```bash
bazel build --verbose_failures --config release :kong_deb

```

Run `bazel clean` to clean the bazel build cache.

#### GPG Signing

GPG singing is supported for the rpm packages (`el*` and `aws*`).

```bash
bazel build //:kong_el8 --action_env=RPM_SIGNING_KEY_FILE --action_env=NFPM_RPM_PASSPHRASE
```

## Cross compiling

Cross compiling is currently only tested on Ubuntu 22.04 x86_64 with following targeting platforms:

- **//:ubuntu-22.04-arm64** Ubuntu 22.04 ARM64
    - Requires user to manually install `crossbuild-essential-arm64`.
- **//:alpine-x86_64** Alpine Linux x86_64; bazel manages the build toolchain.

Make sure platforms are selected both in building Kong and packaing kong:

```bash
bazel build --config release //build:kong --platforms=//:ubuntu-2204-arm64
azel build --config release :kong_deb --platforms=//:ubuntu-2204-arm64
```

## Troubleshooting

Run `bazel build` with `--sandbox_debug --verbose_failures` to get more information about the error.

The `.log` files in `bazel-bin` contain the build logs.

## FAQ

### Caching

Bazel utilizes a cache to speed up the build process. You might want to clear the cache actively
if you recently changed `BUILD_NAME` or `INSTALL_DESTDIR`.

To completely remove the entire working tree created by a Bazel instance, run:

```shell
bazel clean --expunge
```

### Cleanup

In some cases where the build fails or the build is interrupted, the build system may leave behind some temporary files. To clean up the build system, run the following command or simply rerun the build:

```shell
bazel clean
```

