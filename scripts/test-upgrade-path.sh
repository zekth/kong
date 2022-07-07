#!/bin/sh

function usage() {
    cat 1>&2 <<EOF
usage: $0 [-n] <from-version> <to-version>

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

if [ $# -ne 2 ]
then
    echo "Missing <from-version> or <to-version>"
    usage
    exit 1
fi

OLD_VERSION=$1
NEW_VERSION=$2
NETWORK_NAME=migration-$OLD_VERSION-$NEW_VERSION

set -ex

trap "echo exiting because of error" 0

OLD_CONTAINER=$(gojira prefix -t $OLD_VERSION)_kong_1
NEW_CONTAINER=$(gojira prefix -t $NEW_VERSION)_kong_1

mkdir -p upgrade-test-log
cd upgrade-test-log

function build_containers() {
    gojira up -t $OLD_VERSION --network $NETWORK_NAME --$DATABASE > up-$OLD_VERSION.log 2>&1
    gojira run -t $OLD_VERSION make dev > make-dev-$OLD_VERSION.log 2>&1
    gojira up -t $NEW_VERSION --alone --network $NETWORK_NAME --$DATABASE > up-$NEW_VERSION.log 2>&1
    gojira run -t $NEW_VERSION make dev > make-dev-$NEW_VERSION.log 2>&1
}

function run_tests() {
    # Initialize database
    gojira run -t $OLD_VERSION kong migrations reset --yes || true
    gojira run -t $OLD_VERSION kong migrations bootstrap

    # Prepare list of tests to run
    TESTS=$(gojira run -t $NEW_VERSION kong migrations tests)
    if [ "$IGNORE_MISSING_TESTS" = "1" ]
    then
        TESTS=$(gojira run -t $NEW_VERSION "ls 2>/dev/null $TESTS || true")
    fi

    # Make tests available in OLD container
    TESTS_TAR=/tmp/upgrade-tests-$$.tar
    docker exec ${NEW_CONTAINER} tar cf ${TESTS_TAR} spec/upgrade_helpers.lua $TESTS
    docker cp ${NEW_CONTAINER}:${TESTS_TAR} ${TESTS_TAR}
    docker cp ${TESTS_TAR} ${OLD_CONTAINER}:${TESTS_TAR}
    docker exec ${OLD_CONTAINER} tar xf ${TESTS_TAR}
    rm ${TESTS_TAR}

    # Run the tests
    BUSTED="env KONG_TEST_PG_DATABASE=kong bin/busted"

    gojira run -t $OLD_VERSION "$BUSTED -t old_before $TESTS"
    gojira run -t $NEW_VERSION kong migrations up
    gojira run -t $OLD_VERSION "$BUSTED -t old_after_up $TESTS"
    gojira run -t $NEW_VERSION "$BUSTED -t new_after_up $TESTS"
    gojira run -t $NEW_VERSION kong migrations finish
    gojira run -t $NEW_VERSION "$BUSTED -t new_after_finish $TESTS"
}

if [ -z "$NO_BUILD" ]
then
    build_containers
fi
run_tests

trap "" 0
