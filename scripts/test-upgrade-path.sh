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

NETWORK_NAME=migration-$OLD_VERSION-$NEW_VERSION

# Between docker-compose v1 and docker-compose v2, the delimiting
# character for container names was changed from "-" to "_".
if [[ "$(docker-compose --version)" =~ v2 ]]
then
    OLD_CONTAINER=$(gojira prefix -t $OLD_VERSION)-kong-1
    NEW_CONTAINER=$(gojira prefix -t $NEW_VERSION)-kong-1
else
    OLD_CONTAINER=$(gojira prefix -t $OLD_VERSION)_kong_1
    NEW_CONTAINER=$(gojira prefix -t $NEW_VERSION)_kong_1
fi

function build_containers() {
    echo "Building containers"

    gojira up -t $OLD_VERSION --network $NETWORK_NAME --$DATABASE
    gojira run -t $OLD_VERSION -- make dev
    gojira up -t $NEW_VERSION --alone --network $NETWORK_NAME --$DATABASE
    gojira run -t $NEW_VERSION -- make dev
}

function initialize_test_list() {
    echo "Determining tests to run"

    # Prepare list of tests to run
    if [ -z "$TESTS" ]
    then
        all_tests_file=$(mktemp)
        available_tests_file=$(mktemp)

        gojira run -t $NEW_VERSION -- kong migrations status \
            | jq -r '.new_migrations | .[] | (.namespace | gsub("[.]"; "/")) as $namespace | .migrations[] | "\($namespace)/\(.)_spec.lua" | gsub("^kong"; "spec/05-migration")' \
            | sort > $all_tests_file
        gojira run -t $NEW_VERSION -- ls 2>/dev/null $(cat $all_tests_file) \
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
        gojira run -t $OLD_VERSION -- kong migrations reset --yes || true
        gojira run -t $OLD_VERSION -- kong migrations bootstrap

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
        gojira run -t $OLD_VERSION -- $BUSTED -t setup $TEST
        echo ">> Running migrations"
        gojira run -t $NEW_VERSION -- kong migrations up
        echo ">> Testing old_after_up,all_phases"
        gojira run -t $OLD_VERSION -- $BUSTED -t old_after_up,all_phases $TEST
        echo ">> Testing new_after_up,all_phases"
        gojira run -t $NEW_VERSION -- $BUSTED -t new_after_up,all_phases $TEST
        echo ">> Finishing migrations"
        gojira run -t $NEW_VERSION -- kong migrations finish
        echo ">> Testing new_after_finish,all_phases"
        gojira run -t $NEW_VERSION -- $BUSTED -t new_after_finish,all_phases $TEST

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
