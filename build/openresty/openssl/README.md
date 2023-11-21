This target is modified from https://github.com/bazelbuild/rules_foreign_cc/tree/main/examples/third_party
with following changes:

- Read version from requirements.txt
- Updated `build_file` to new path under //build/openresty
- Remove Windows build support
- Removed the bazel mirror as it's missing latest versions
- Remove runnable test for now until cross compile has been sorted out
- Use system Perl for now
- Updated to be reusable