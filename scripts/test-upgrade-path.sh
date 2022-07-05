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

FROM_VERSION=$1
FROM_TAG=$FROM_VERSION
TO_VERSION=$2
TO_TAG=${branch:-$TO_VERSION}
NETWORK_NAME=migration-$FROM_TAG-$TO_TAG

set -ex

trap "echo exiting because of error" 0

FROM_KONG_CONTAINER=$(gojira prefix -t $FROM_TAG)_kong_1
TO_KONG_CONTAINER=$(gojira prefix -t $TO_TAG)_kong_1
UPGRADE_TEST_DIR=/kong/spec/05-upgrade
UPGRADE_TEST_FILE=upgrade-$FROM_VERSION-${TO_VERSION}_spec.lua

BUSTED="env KONG_TEST_PG_DATABASE=kong bin/busted"

mkdir -p upgrade-test-log
cd upgrade-test-log

function build_containers() {
    gojira up -t $FROM_TAG --network $NETWORK_NAME --$DATABASE > up-$FROM_TAG.log 2>&1
    gojira run -t $FROM_TAG make dev > make-dev-$FROM_TAG.log 2>&1
    gojira up -t $TO_TAG --alone --network $NETWORK_NAME --$DATABASE > up-$TO_TAG.log 2>&1
    gojira run -t $TO_TAG make dev > make-dev-$TO_TAG.log 2>&1
}

function run_tests() {
    # Copy upgrade test from target version every time we run the
    # tests as it may have been edited during development
    docker cp ${TO_KONG_CONTAINER}:$UPGRADE_TEST_DIR/$UPGRADE_TEST_FILE /tmp
    docker cp /tmp/$UPGRADE_TEST_FILE ${FROM_KONG_CONTAINER}:/tmp
    gojira run -t $FROM_TAG kong migrations reset --yes || true
    gojira run -t $FROM_TAG kong migrations bootstrap
    gojira run -t $TO_TAG kong migrations up
    gojira run -t $FROM_TAG "$BUSTED -t before /tmp/$UPGRADE_TEST_FILE"
    gojira run -t $TO_TAG "$BUSTED -t migrating $UPGRADE_TEST_DIR/$UPGRADE_TEST_FILE"
    gojira run -t $TO_TAG kong migrations finish
    gojira run -t $TO_TAG "$BUSTED -t after $UPGRADE_TEST_DIR/$UPGRADE_TEST_FILE"
}

if [ -z "$no_build" ]
then
    build_containers
fi
run_tests

trap "" 0
