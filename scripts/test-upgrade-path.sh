#!/bin/bash

set -e

trap "echo exiting because of error" 0

function usage() {
    cat 1>&2 <<EOF
usage: $0 [-n] <from-version> <to-version> [ <test> ... ]

 <from-version> and <to-version> need to be git versions

 Options:
   -n                     just run the tests, don't build containers (they need to already exist)
   -i                     proceed even if not all migrations have tests
   -d postgres|cassandra  select database type

EOF
}

DATABASE=postgres

args=$(getopt nd:i $*)
if [ $? -ne 0 ]
then
    usage
    exit 1
fi
set -- $args

while :; do
    case "$1" in
        -n)
            NO_BUILD=1
            shift
            ;;
        -d)
            DATABASE=$2
            shift
            shift
            ;;
        -i)
            IGNORE_MISSING_TESTS=1
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

if [ $# -lt 2 ]
then
    echo "Missing <from-version> or <to-version>"
    usage
    exit 1
fi

OLD_VERSION=$1
NEW_VERSION=$2
shift ; shift
TESTS=$*

ENV_PREFIX=${UPGRADE_ENV_PREFIX:-$(openssl rand -hex 8)}

COMPOSE="docker compose -p $ENV_PREFIX -f scripts/upgrade-tests.yml"

NETWORK_NAME=migration-$OLD_VERSION-$NEW_VERSION

OLD_CONTAINER=$ENV_PREFIX-kong_old-1
NEW_CONTAINER=$ENV_PREFIX-kong_new-1

function prepare_container() {
    docker exec $1 apt-get update
    docker exec $1 apt-get install -y build-essential curl m4
    docker exec $1 ln -sf /usr/lib/x86_64-linux-gnu/librt.so /usr/local/lib
    docker exec $1 bash -c "ln -sf /usr/local/kong/include/* /usr/include"
    docker exec $1 bash -c "ln -sf /usr/local/kong/lib/* /usr/lib"
}

function build_containers() {
    echo "Building containers"

    [ -d worktree/$OLD_VERSION ] || git worktree add worktree/$OLD_VERSION $OLD_VERSION
    [ -d worktree/$NEW_VERSION ] || git worktree add worktree/$NEW_VERSION $NEW_VERSION
    OLD_KONG_VERSION=$OLD_VERSION \
               OLD_KONG_IMAGE=kong:$OLD_VERSION-ubuntu \
               NEW_KONG_VERSION=$NEW_VERSION \
               NEW_KONG_IMAGE=kong:$NEW_VERSION-ubuntu \
               $COMPOSE up --wait
    prepare_container $OLD_CONTAINER
    prepare_container $NEW_CONTAINER
    docker exec -w /kong $OLD_CONTAINER make dev CRYPTO_DIR=/usr/local/kong
    # Kong version >= 3.3 moved non Bazel-built dev setup to make dev-legacy
    docker exec -w /kong $NEW_CONTAINER make dev-legacy CRYPTO_DIR=/usr/local/kong
}

function initialize_test_list() {
    echo "Determining tests to run"

    # Prepare list of tests to run
    if [ -z "$TESTS" ]
    then
        all_tests_file=$(mktemp)
        available_tests_file=$(mktemp)

        docker exec $NEW_CONTAINER kong migrations status \
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
    docker exec ${OLD_CONTAINER} tar -xf ${TESTS_TAR} -C /kong
    rm ${TESTS_TAR}
}

function run_tests() {
    # Run the tests
    BUSTED="env KONG_DNS_RESOLVER= KONG_TEST_CASSANDRA_KEYSPACE=kong KONG_TEST_PG_DATABASE=kong bin/busted -o gtest"

    while true
    do
        # Initialize database
        docker exec $OLD_CONTAINER kong migrations reset --yes || true
        docker exec $OLD_CONTAINER kong migrations bootstrap

        if [ -z "$TEST_LIST_INITIALIZED" ]
        then
           initialize_test_list
           TEST_LIST_INITIALIZED=1
           set $TESTS
        fi

        # Run test
        TEST=$1
        shift

        echo
        echo --------------------------------------------------------------------------------
        echo Running $TEST

        echo ">> Setting up tests"
        docker exec -w /kong $OLD_CONTAINER $BUSTED -t setup $TEST
        echo ">> Running migrations"
        docker exec $NEW_CONTAINER kong migrations up
        echo ">> Testing old_after_up,all_phases"
        docker exec -w /kong $OLD_CONTAINER $BUSTED -t old_after_up,all_phases $TEST
        echo ">> Testing new_after_up,all_phases"
        docker exec -w /kong $NEW_CONTAINER $BUSTED -t new_after_up,all_phases $TEST
        echo ">> Finishing migrations"
        docker exec $NEW_CONTAINER kong migrations finish
        echo ">> Testing new_after_finish,all_phases"
        docker exec -w /kong $NEW_CONTAINER $BUSTED -t new_after_finish,all_phases $TEST

        if [ -z "$1" ]
        then
            break
        fi
    done
}

if [ -z "$NO_BUILD" ]
then
    build_containers
fi
run_tests

trap "" 0
