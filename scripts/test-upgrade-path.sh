#!/bin/sh

function usage() {
    cat <<EOF
usage: $0 [-n] <from-version> <to-version>

 <from-version> and <to-version> need to be git versions

 Options:
   -n do not build containers, just run the tests

EOF
}

DATABASE=postgres

args=$(getopt nmd:b: $*)
if [ $? -ne 0 ]
then
    usage
    exit 1
fi
set -- $args

while :; do
    case "$1" in
        -n)
            no_build=1
            shift
            ;;
        -m)
            branch=master
            shift
            ;;
        -b)
            branch=$2
            shift
            shift
            ;;
        -d)
            DATABASE=$2
            shift
            shift
            ;;
        --)
            shift
            break
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
OLD_TAG=$OLD_VERSION
NEW_VERSION=$2
NEW_TAG=${branch:-$NEW_VERSION}
NETWORK_NAME=migration-$OLD_TAG-$NEW_TAG

set -ex

trap "echo exiting because of error" 0

OLD_CONTAINER=$(gojira prefix -t $OLD_TAG)_kong_1
NEW_CONTAINER=$(gojira prefix -t $NEW_TAG)_kong_1

mkdir -p upgrade-test-log
cd upgrade-test-log

function build_containers() {
    gojira up -t $OLD_TAG --network $NETWORK_NAME --$DATABASE > up-$OLD_TAG.log 2>&1
    gojira run -t $OLD_TAG make dev > make-dev-$OLD_TAG.log 2>&1
    gojira up -t $NEW_TAG --alone --network $NETWORK_NAME --$DATABASE > up-$NEW_TAG.log 2>&1
    gojira run -t $NEW_TAG make dev > make-dev-$NEW_TAG.log 2>&1
}

function run_tests() {
    # Copy upgrade test from target version every time we run the
    # tests as it may have been edited during development

    gojira run -t $OLD_TAG kong migrations reset --yes || true
    gojira run -t $OLD_TAG kong migrations bootstrap
    TESTS=$(gojira run -t $NEW_TAG kong migrations tests)

    BUSTED="env KONG_TEST_PG_DATABASE=kong TARGET_HOST=${OLD_CONTAINER} bin/busted"

    gojira run -t $OLD_TAG kong restart
    gojira run -t $NEW_TAG "$BUSTED -t old_before $TESTS"
    gojira run -t $OLD_TAG kong stop

    gojira run -t $NEW_TAG kong migrations up

    gojira run -t $OLD_TAG kong restart
    gojira run -t $NEW_TAG "$BUSTED -t old_after_up $TESTS"
    gojira run -t $OLD_TAG kong stop

    BUSTED="env KONG_TEST_PG_DATABASE=kong TARGET_HOST=${NEW_CONTAINER} bin/busted"

    gojira run -t $NEW_TAG kong start
    gojira run -t $NEW_TAG "$BUSTED -t new_after_up $TESTS"
    gojira run -t $NEW_TAG kong stop

    gojira run -t $NEW_TAG kong migrations finish

    gojira run -t $NEW_TAG kong start
    gojira run -t $NEW_TAG "$BUSTED -t new_after_finish $TESTS"
    gojira run -t $NEW_TAG kong stop
}

if [ -z "$no_build" ]
then
    build_containers
fi
run_tests

trap "" 0
