#!/bin/sh

# When users are faced with large merges, they will sometimes split
# the merge across several commits so that they don't have to start
# from scratch if they make a mistake.  This is known as a "piecemeal
# merge".

# The recommended way of representing this is to amend the revisions
# together, and merge at the end.  This is based on the assumption
# that the user would ideally have only committed one revision, but
# was forced to commit extra revisions as a temporary safety net.
# It's recommended to put the merge action at the end, as the merge
# isn't complete until then.

# Note: there was no known way of automatically detecting piecemeal
# merges at the time of writing.

config() {

    SVN="$1"

    # Initialise the repository:
    mkdir trunk branches tags
    mkdir trunk/foo trunk/bar
    touch trunk/foo/foo.c trunk/bar/bar.c
    "$SVN" add trunk branches tags
    "$SVN" ci -m "Initial revision"

    # Copy the trunk:
    "$SVN" cp trunk branches/branch_of_trunk
    "$SVN" ci -m "Created branch_of_trunk"

    # Make some changes that will be hard and error-prone to merge back:
    echo "Hard-to-merge changes" > branches/branch_of_trunk/foo/foo.c
    echo "Hard-to-merge changes" > branches/branch_of_trunk/bar/bar.c
    mkdir branches/branch_of_trunk/baz
    touch branches/branch_of_trunk/baz/baz.c
    "$SVN" add branches/branch_of_trunk/baz
    "$SVN" ci -m "Hard-to-merge changes"

    # Do the first part of the merge, and commit the changes so they're safe:
    "$SVN" merge branches/branch_of_trunk/foo trunk/foo
    "$SVN" ci -m "Merge branch_of_trunk -> trunk (1/3)"

    # Do the second part of the merge, and commit the changes so they're safe:
    "$SVN" merge branches/branch_of_trunk/bar trunk/bar
    "$SVN" ci -m "Merge branch_of_trunk -> trunk (2/3)"

    # It turns out the final part of the merge isn't actually a merge at all:
    "$SVN" cp branches/branch_of_trunk/new_file trunk/new_file
    "$SVN" ci -m "Merge branch_of_trunk -> trunk (3/3)"

}

expect_representation "Piecemeal merge" < <<EOF
This is a version 0.1 SVN Branching Language file
Body:
In r1, create branch "trunk"
In r2, create branch "branches/branch_of_trunk" from "trunk"
In r5, amend "branches/branch_of_trunk"
In r6, amend "branches/branch_of_trunk"
In r6, merge "branches/branch_of_trunk" r5 into "trunk"
EOF
