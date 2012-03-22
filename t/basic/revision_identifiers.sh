#!/bin/sh

# Test various valid and invalid revision identifiers

config() {

    SVN="$1"

    "$SVN" add trunk
    "$SVN" ci -m "Revision 1 creates trunk"

}

expect_ok "this is the only valid revision identifier" <<EOF
This is a version 0.1 SVN Branch Description file
Body:
In r1, create branch "trunk"
EOF

expect_fatal_error "uppercase 'r' is not valid in a revision identifier" <<EOF
This is a version 0.1 SVN Branch Description file
Body:
In R1, create branch "trunk"
EOF

expect_fatal_error "revision numbers cannot begin with a zero" <<EOF
This is a version 0.1 SVN Branch Description file
Body:
In r01, create branch "trunk"
EOF

expect_fatal_error "revision numbers must not be zero" <<EOF
This is a version 0.1 SVN Branch Description file
Body:
In r0, create branch "trunk"
EOF

expect_fatal_error "revision numbers must be negative" <<EOF
This is a version 0.1 SVN Branch Description file
Body:
In r-1, create branch "trunk"
EOF

expect_fatal_error "'revision ' is not valid in a revision identifier" <<EOF
This is a version 0.1 SVN Branch Description file
Body:
In revision 1, create branch "trunk"
EOF

expect_fatal_error "The 'r' must be present in a revision identifier" <<EOF
This is a version 0.1 SVN Branch Description file
Body:
In 1, create branch "trunk"
EOF
