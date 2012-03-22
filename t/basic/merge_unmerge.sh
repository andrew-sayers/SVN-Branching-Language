#!/bin/sh

# It's often necessary to merge branches together, and sometimes
# necessary to undo those merges.  Undoing a merge should be
# represented as a "revert" action on the merge revision.

config() {

    SVN="$1"
    REPOSITORY_URL="$2"

    # Initialise the repository:
    mkdir trunk branches tags
    touch trunk/main.c
    "$SVN" add trunk branches tags
    "$SVN" ci -m "Initial revision"

    # Copy the trunk:
    "$SVN" cp trunk branches/branch_of_trunk
    "$SVN" ci -m "Created branch_of_trunk"

    # Make some changes that will be hard and error-prone to merge back:
    echo "changes" > branches/main.c
    "$SVN" ci -m "Changes"

    "$SVN" merge branches/branch_of_trunk trunk
    "$SVN" ci -m "Merge branch_of_trunk -> trunk" # r4

    "$SVN" merge -c -4 "$REPOSITORY_URL/trunk" trunk

}

expect_representation "Piecemeal merge" < <<EOF
This is a version 0.1 SVN Branching Language file
Body:
In r1, create branch "trunk"
In r2, create branch "branches/branch_of_trunk" from "trunk"
In r4, merge "branches/branch_of_trunk" r3 into "trunk"
In r5, revert "trunk" r4 from "trunk"
EOF
