#!/bin/sh

# Test various valid/invalid directories and names

config() {

    SVN="$1"

    "$SVN" add trunk
    "$SVN" ci -m "Revision 1 creates trunk"

}

expect_fatal_error "empty names are not allowed" <<EOF
This is a version 0.1 SVN Branch Description file
Body:
In r1, create branch "trunk" as ""
EOF

expect_fatal_error "the root directory must have a name" <<EOF
This is a version 0.1 SVN Branch Description file
Body:
In r1, create branch ""
EOF

expect_ok "The directory '/' is equivalent to ''" <<EOF
This is a version 0.1 SVN Branch Description file
Body:
In r1, create branch "/" as "root"
EOF

expect_ok "directories can end with a '/'" <<EOF
This is a version 0.1 SVN Branch Description file
Body:
In r1, create branch "trunk/" as "trunk"
EOF

printf "This is a version 0.1 SVN Branch Description file
Body:
In r1, create branch \"\0\"
" | expect_fatal_error "the null character is not allowed in directories"

printf "This is a version 0.1 SVN Branch Description file
Body:
In r1, create branch \"trunk\" as \"tr\0nk\"
" | expect_fatal_error "the null character is not allowed in names"

expect_ok "the root directory can be a branch" <<EOF
This is a version 0.1 SVN Branch Description file
Body:
In r1, create branch "" as "root"
EOF

expect_ok "directories don't have to exist before they are active" <<EOF
This is a version 0.1 SVN Branch Description file
Body:
In r1, create branch "branch-that-does-not-exist"
EOF
