This target is modified from hhttps://github.com/envoyproxy/envoy/tree/main/bazel/external
with following changes:

- Read version from requirements.txt
- Path prefix changed from `boringssl` to `boringssl_fips`
- Output both version suffixed and non-suffixed shared libraries
