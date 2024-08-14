#!/usr/bin/env bash

# We're not setting KONG_SPEC_TEST_REDIS_CLUSTER_ADDRESSES here as it is set int Kong/kong-pongo:
# https://github.com/Kong/kong-pongo/blob/af563c4d79d4cff6061e16df77261f9f231555f7/assets/pongo_entrypoint.sh#L76
# Probably something worth refactoring in the future as this is a test dependency not a kong-pongo feature
# -------
# export KONG_SPEC_TEST_REDIS_CLUSTER_ADDRESSES
# -------

export KONG_SPEC_TEST_REDIS_SENTINEL_ADDRESSES=redis-sentinel:27000,redis-sentinel:27001,redis-sentinel:27002
