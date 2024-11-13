#!/bin/bash

# This script runs the database upgrade tests from the
# spec/05-migration directory.  It uses docker compose to stand up a
# simple environment with postgres database server and a Kong node.
# The node contains the oldest supported version, the current version
# of Kong is accessed via the local virtual environment. The testing is then
# done as described in https://docs.google.com/document/d/1Df-iq5tNyuPj1UNG7bkhecisJFPswOfFqlOS3V4wXSc/edit?usp=sharing

# Normally, the testing environment and the git worktree that is
# required by this script are removed when the tests have run.  By
# setting the UPGRADE_ENV_PREFIX environment variable, the docker
# compose environment's prefix can be defined.  The environment will
# then not be automatically cleaned, which is useful during test
# development as it greatly speeds up test runs.

# Optionally, the test to run can be specified as a command line
# option.  If it is not specified, the script will determine the tests
# to run based on the migration steps that are performed during the
# database up migration from the base to the current version.

set -e

trap "echo exiting because of error" 0

export KONG_PG_HOST=localhost
export KONG_TEST_PG_HOST=localhost

function usage() {
    cat 1>&2 <<EOF
usage: $0 [ -i <venv-script> ] [ <test> ... ]

 <venv-script> Script to source to set up Kong's virtual environment.
EOF
}

args=$(getopt i: $*)
if [ $? -ne 0 ]
then
    usage
    exit 1
fi
set -- $args

while :; do
    case "$1" in
        -i)
            venv_script=$2
            shift
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

TESTS=$*

ENV_PREFIX=${UPGRADE_ENV_PREFIX:-$(openssl rand -hex 8)}

COMPOSE="docker compose -p $ENV_PREFIX -f scripts/upgrade-tests/docker-compose.yml"

NETWORK_NAME=$ENV_PREFIX

OLD_CONTAINER=$ENV_PREFIX-kong_old-1

function prepare_container() {
    docker exec $1 apt-get update
    docker exec $1 apt-get install -y build-essential curl m4 unzip git
    docker exec $1 bash -c "ln -sf /usr/local/kong/include/* /usr/include"
    docker exec $1 bash -c "ln -sf /usr/local/kong/lib/* /usr/lib"
}

function build_containers() {
    # Kong version >= 3.3 moved non Bazel-built dev setup to make dev-legacy
    if (( $(echo "$OLD_KONG_VERSION" | sed 's/\.//g') >= 330 )); then
        old_make_target="dev-legacy"
    else
        old_make_target="dev"
    fi

    echo "Building containers"

    [ -d worktree/$OLD_KONG_VERSION ] || git worktree add worktree/$OLD_KONG_VERSION $OLD_KONG_VERSION
    $COMPOSE up --wait
    prepare_container $OLD_CONTAINER
    docker exec -w /kong $OLD_CONTAINER make $old_make_target CRYPTO_DIR=/usr/local/kong
    make dev-legacy CRYPTO_DIR=/usr/local/kong
}

function initialize_test_list() {
    echo "Determining tests to run"

    # Prepare list of tests to run
    if [ -z "$TESTS" ]
    then
        all_tests_file=$(mktemp)
        available_tests_file=$(mktemp)

        docker exec $OLD_CONTAINER kong migrations reset --yes || true
        docker exec $OLD_CONTAINER kong migrations bootstrap
        kong migrations status \
            | jq -r '.new_migrations | .[] | (.namespace | gsub("[.]"; "/")) as $namespace | .migrations[] | "\($namespace)/\(.)_spec.lua" | gsub("^kong"; "spec/05-migration")' \
            | sort > $all_tests_file
        ls 2>/dev/null $(cat $all_tests_file) \
            | sort > $available_tests_file

        if [ "$IGNORE_MISSING_TESTS" = "1" ]
        then
            TESTS=$(cat $available_tests_file)
        else
            if ! cmp -s $available_tests_file $all_tests_file
            then
                echo "Not all migrations have corresponding tests, cannot continue.  Missing test(s):"
                echo
                comm -13 $available_tests_file $all_tests_file \
                     | perl -pe 's/^/    /g'
                echo
                rm $available_tests_file $all_tests_file
                exit 1
            fi
            TESTS=$(cat $all_tests_file)
        fi
        rm $available_tests_file $all_tests_file
    fi

    echo "Going to run:"
    echo $TESTS | perl -pe 's/(^| )/\n    /g'

    # Make tests available in OLD container
    TESTS_TAR=/tmp/upgrade-tests-$$.tar
    tar cf ${TESTS_TAR} spec/upgrade_helpers.lua $TESTS
    docker cp ${TESTS_TAR} ${OLD_CONTAINER}:${TESTS_TAR}
    docker exec ${OLD_CONTAINER} mkdir -p /upgrade-test/bin /upgrade-test/spec
    docker exec ${OLD_CONTAINER} ln -sf /kong/bin/kong /upgrade-test/bin
    docker exec ${OLD_CONTAINER} bash -c "ln -sf /kong/spec/* /upgrade-test/spec"
    docker exec ${OLD_CONTAINER} tar -xf ${TESTS_TAR} -C /upgrade-test
    docker cp spec/helpers/http_mock ${OLD_CONTAINER}:/upgrade-test/spec/helpers
    docker cp spec/helpers/http_mock.lua ${OLD_CONTAINER}:/upgrade-test/spec/helpers
    rm ${TESTS_TAR}
}

function run_tests() {
    # Run the tests
    BUSTED_ENV="env KONG_DATABASE=$1 KONG_DNS_RESOLVER= KONG_TEST_PG_DATABASE=kong OLD_KONG_VERSION=$OLD_KONG_VERSION"

    shift

    set $TESTS

    for TEST in $TESTS
    do
        docker exec $OLD_CONTAINER kong migrations reset --yes || true
        docker exec $OLD_CONTAINER kong migrations bootstrap

        echo
        echo --------------------------------------------------------------------------------
        echo Running $TEST

        echo ">> Setting up tests"
        docker exec -w /upgrade-test $OLD_CONTAINER $BUSTED_ENV /kong/bin/busted -t setup $TEST
        echo ">> Running migrations"
        kong migrations up --force
        echo ">> Testing old_after_up,all_phases"
        docker exec -w /upgrade-test $OLD_CONTAINER $BUSTED_ENV /kong/bin/busted -t old_after_up,all_phases $TEST
        echo ">> Testing new_after_up,all_phases"
        $BUSTED_ENV bin/busted -t new_after_up,all_phases $TEST
        echo ">> Finishing migrations"
        kong migrations finish
        echo ">> Testing new_after_finish,all_phases"
        $BUSTED_ENV bin/busted -t new_after_finish,all_phases $TEST
    done
}

function cleanup() {
    sudo git worktree remove worktree/$OLD_KONG_VERSION --force
    $COMPOSE down
}


source $venv_script

# Load supported "old" versions to run migration tests against
old_versions=()
mapfile -t old_versions < "scripts/upgrade-tests/source-versions"

for old_version in "${old_versions[@]}"; do
    export OLD_KONG_VERSION=$old_version
    export OLD_KONG_IMAGE=kong:$OLD_KONG_VERSION-ubuntu

    echo "Running tests using $OLD_KONG_VERSION as \"old version\" of Kong"

    build_containers
    initialize_test_list
    run_tests postgres
    [ -z "$UPGRADE_ENV_PREFIX" ] && cleanup
done

deactivate

trap "" 0
