#!/bin/bash

set -e

# EE only:
# bytecompile
distribution/post-bytecompile.sh

# add copyright manifests
distribution/post-copyright-manifests.sh
