#!/bin/bash

set -e

# This script is from the Kong/kong-build-tools repo, and is used to patch the Kong Enterprise.

# EE only:
# bytecompile
distribution/post-bytecompile.sh

# add copyright manifests
distribution/post-copyright-manifests.sh
