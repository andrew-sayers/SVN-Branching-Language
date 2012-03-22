#!/bin/sh

# Most clients assume that recursive branches are impossible, but it
# is not unheard of for a sub-directories of one branch to be split
# into its own new branch.  For example, this could happen if a
# seemingly minor bit of code turned out to be the solution to a
# problem of general interest.
#
# This is known as a "subproject branch", and clients that choose the
# sanity-preserving approach of disallowing recursive branches are
# encouraged to treat them simply as a branch of the original project.
# This keeps a sensible log, and allows a sufficiently advanced
# version control system to spot the directory shuffle.
#
# Since this is not a perfect solution, clients may want to get
# confirmation from the user when they see a subproject branch.

config() {

    SVN="$1"

    mkdir trunk branches tags
    touch trunk/main.c
    mkdir trunk/sub_project
    touch trunk/sub_project/main.c
    "$SVN" add trunk branches tags
    "$SVN" ci -m "Initial revision"
    "$SVN" cp trunk/sub_project branches/sub_project
    "$SVN" ci -m "Split sub_project into its own branch"

}

expect_representation "Delayed standard layout" < <<EOF
This is a version 0.1 SVN Branch Description file
Body:
In r1, create branch "trunk"
In r2, create branch "branches/sub_project" as "sub_project" from "trunk"
EOF
