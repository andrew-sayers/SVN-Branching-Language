#!/bin/sh

# When a *.c file is created, clients should rewind their history to
# find the appropriate trunk.  Even though there might not be any
# files to store, the revision log needs to be kept.

config() {

    SVN="$1"

    mkdir tronk brunches tigs
    "$SVN" add tronk brunches tigs
    "$SVN" ci -m "Valuable revision log message that should be kept"
    "$SVN" mv tronk trunk
    "$SVN" ci -m "Fixed typo"
    touch trunk/main.c
    "$SVN" ci -m "main.c created after initial revision"

}

expect_representation "Delayed standard layout" < <<EOF
This is a version 0.1 SVN Branching Language file
Body:
In r1, create branch "tronk"
In r2, create branch "trunk" from "tronk"
EOF
