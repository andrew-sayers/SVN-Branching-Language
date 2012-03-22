#!/bin/sh

# When a directory is deleted then recreated, there are several valid
# ways to represent that, and also some invalid ways.
#
# Test that the parser accepts all (and only) the valid
# representations.

config() {

    SVN="$1"

    "$SVN" add trunk
    "$SVN" ci -m "Revision 1 creates trunk"
    "$SVN" add trunk/README.txt
    "$SVN" ci -m "Revision 2 changes trunk"
    "$SVN" rm trunk
    "$SVN" ci -m "Revision 3 removes trunk"
    "$SVN" add trunk
    "$SVN" ci -m "Revision 4 re-creates trunk"

}

expect_fatal_error "branch already exists" < <<EOF
This is a version 0.1 SVN Branch Description file
Body:
In r2, create branch "trunk" as "I_am_trunk"
In r3, deactivate "trunk"
In r4, create branch "trunk" as "I_am_trunk"
EOF


expect_fatal_error "no such tag" < <<EOF
This is a version 0.1 SVN Branch Description file
Body:
In r2, create branch "trunk" as "I_am_trunk"
In r3, deactivate "trunk"
In r4, deactivate tag "I_am_trunk"
In r4, create branch "trunk" as "I_am_trunk"
EOF


expect_ok "branch deleted then recreated" < <<EOF
This is a version 0.1 SVN Branch Description file
Body:
In r2, create branch "trunk" as "I_am_trunk"
In r3, deactivate "trunk"
In r4, delete branch "I_am_trunk"
In r4, create branch "trunk" as "I_am_trunk"
EOF


expect_ok "different branch name" < <<EOF
This is a version 0.1 SVN Branch Description file
Body:
In r2, create branch "trunk" as "I_am_trunk"
In r3, deactivate "trunk"
In r4, create branch "trunk"
EOF


expect_ok "tag instead of branch" < <<EOF
This is a version 0.1 SVN Branch Description file
Body:
In r2, create branch "trunk" as "I_am_trunk"
In r3, deactivate "trunk"
In r4, create tag "trunk" as "I_am_trunk"
EOF