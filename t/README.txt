This directory contains tests for SBL clients.

The "basic" directory contains standard scenarios that clients all
clients must pass.

The "advanced" directory is a collection of edge cases that authors
should consider when writing a client.  Clients can comply with the
spec without passing any of these tests, but authors are recommended
to read through them and understand what their client will do when it
meets them.

Some clients need the user to delcare things about the repository,
such as trunks and branches.  The tests all use the same terminology,
so that clients can be configured to "just know" and have to learn
other things.


trunk::
  Clients should "just know" that this is directory is a trunk

my_project[1-9]/trunk::
  Clients should "just know" these are trunks for different
  projects in one repository

branches::
  Clients should "just know" that sub-directories of this directory
  are more likely to be branches than tags.  However, sub-directories
  can be neither branches nor tags (e.g. in "branches/v1.x/v1.0",
  "branches/v1.x" is not a branch)

tags::
  Clients should "just know" that sub-directories of this directory
  are more likely to be tags than branches.  However, sub-directories
  can be neither tags nor tags (e.g. in "tags/v1.x/v1.0", "tags/v1.x"
  is not a tag)

myproject[1-9]/branches::
myproject[1-9]/tags::
  Clients should "just know" these directories contain branches/tags
  for the associated project

*.c::
  Clients should "just know" that these files can only occur inside a
  branch or tag.  Clients can use this information to calculate which
  directories are branches.

README.txt::
  Clients should ignore this file for the purposes of calculating
  branches and tags - they can appear anywhere in a repository, even
  outside branches and tags

branch_of_trunk, branch/of_trunk and branch/of/trunk::
  These are branches directly from the trunk branch.  Clients must not
  "just know" that these are branches - they should calculate it from
  the available information

tag_of_trunk, tag/of_trunk and tag/of/trunk::
  These are tags directly from the trunk tag.  Clients must not
  "just know" that these are tags - they should calculate it from
  the available information

nonstandard_directory[1-9]::
  This directory may or may not be a branch or tag.  Clients must not
  "just know" anything about these - they should calculate it from the
  available information

tronk, brunches and tigs::
  Clients must treat these the same as "nonstandard_directory", but
  they actually indicate misspellings of "trunk", "branches" and
  "tags" - these recognisable typos are just used to make examples
  more readable
