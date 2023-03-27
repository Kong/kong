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

ENV_PREFIX=$(openssl rand -hex 8)

NETWORK_NAME=migration-$OLD_VERSION-$NEW_VERSION

# Between docker-compose v1 and docker-compose v2, the delimiting
# character for container names was changed from "-" to "_".
if [[ "$(docker-compose --version)" =~ v2 ]]
then
    OLD_CONTAINER=$ENV_PREFIX-kong_old-1
    NEW_CONTAINER=$ENV_PREFIX-kong_new-1
else
    OLD_CONTAINER=$ENV_PREFIX_kong_old_1
    NEW_CONTAINER=$ENV_PREFIX_kong_new_1
fi

function build_containers() {
    echo "Building containers"

    cd scripts/upgrade_tests
    OLD_KONG_IMAGE=kong:$OLD_VERSION NEW_KONG_IMAGE=kong:$NEW_VERSION docker-compose -p $ENV_PREFIX up
    #gojira run -t $OLD_VERSION -- make dev
    # Kong version >= 3.3 moved non Bazel-built dev setup to make dev-legacy
    #gojira run -t $NEW_VERSION -- make dev-legacy
}

function initialize_test_list() {
    echo "Determining tests to run"

    # Prepare list of tests to run
    if [ -z "$TESTS" ]
    then
        all_tests_file=$(mktemp)
        available_tests_file=$(mktemp)

        docker exec $NEW_CONTAINER -- kong migrations status \
            | jq -r '.new_migrations | .[] | (.namespace | gsub("[.]"; "/")) as $namespace | .migrations[] | "\($namespace)/\(.)_spec.lua" | gsub("^kong"; "spec/05-migration")' \
            | sort > $all_tests_file
        docker exec $NEW_CONTAINER -- ls 2>/dev/null $(cat $all_tests_file) \
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
    docker exec ${NEW_CONTAINER} tar cf ${TESTS_TAR} spec/upgrade_helpers.lua $TESTS
    docker cp ${NEW_CONTAINER}:${TESTS_TAR} ${TESTS_TAR}
    docker cp ${TESTS_TAR} ${OLD_CONTAINER}:${TESTS_TAR}
    docker exec ${OLD_CONTAINER} tar xf ${TESTS_TAR}
    rm ${TESTS_TAR}
}

function run_tests() {
    # Run the tests
    BUSTED="env KONG_DNS_RESOLVER= KONG_TEST_CASSANDRA_KEYSPACE=kong KONG_TEST_PG_DATABASE=kong bin/busted"

    while true
    do
        # Initialize database
        docker exec $OLD_CONTAINER -- kong migrations reset --yes || true
        docker exec $OLD_CONTAINER -- kong migrations bootstrap

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
        docker exec $OLD_CONTAINER -- $BUSTED -t setup $TEST
        echo ">> Running migrations"
        docker exec $NEW_CONTAINER -- kong migrations up
        echo ">> Testing old_after_up,all_phases"
        docker exec $OLD_CONTAINER -- $BUSTED -t old_after_up,all_phases $TEST
        echo ">> Testing new_after_up,all_phases"
        docker exec $NEW_CONTAINER -- $BUSTED -t new_after_up,all_phases $TEST
        echo ">> Finishing migrations"
        docker exec $NEW_CONTAINER -- kong migrations finish
        echo ">> Testing new_after_finish,all_phases"
        docker exec $NEW_CONTAINER -- $BUSTED -t new_after_finish,all_phases $TEST

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
