#!/bin/sh

# This is the most standard behaviour in SVN

config() {

    SVN="$1"

    mkdir trunk branches tags
    touch trunk/main.c
    "$SVN" add trunk branches tags
    "$SVN" ci -m "Initial revision"
    "$SVN" copy trunk branches/branch_of_trunk
    "$SVN" ci -m "Created branches/branch_of_trunk"
    "$SVN" copy trunk tags/tag_of_trunk
    "$SVN" ci -m "Created tags/tag_of_trunk"

}

expect_representation "Standard layout" < <<EOF
This is a version 0.1 SVN Branching Language file
Body:
In r1, create branch "trunk"
In r2, create branch "branches/branch_of_trunk" as "branch_of_trunk" from "trunk" r1
In r3, create tag "tags/tag_of_trunk" as "tag_of_trunk" from "trunk" r2
EOF
