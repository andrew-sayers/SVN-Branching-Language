package SVN::BranchingLanguage;

=head1 NAME

SVN::BranchingLanguage - read and write SBL files

=head1 SYNOPSIS

Create a file for reading:

my $reader = SVN::BranchExport->new(

    file                       => $my_fh,
    client_specific_identifier => "my-great-parser",
    fatal_error                => \&fatal_error,
    warning                    => \&warning,
    new_revision               => \&read_revisions_from_svn,

);

my $header_actions = $reader->get_header;


# Register a change in all affected branches:
$reader->change_path     ( "trunk/doc/README.txt", 123 );
# Register a change in the specified branch:
$reader->change_directory( "trunk"               , 123 );

while ( my $action = $reader->get_body_action ) {
    # do something with this body action
}

=head2 callbacks

The "fatal_error" callback is called when a fatal error (as defined by
the spec) is encountered.  Here is an example implementation:

sub fatal_error {

    my ( $line_number, $error_message ) = @_;

    die "Error at line $line_number: $error_message";

}

The "warning" callback is called when a warning (as defined by
the spec) is encountered.  Here is an example implementation:

sub warning {

    my ( $line_number, $error_message ) = @_;

    warn "Error at line $line_number: $error_message";

}

The "new_revision" callback is called when a new revision number
is seen in the file.  Here is an example implementation:

sub new_revision {

    my ( $rev_no ) = @_;

    while ( $svn_repository_reader->rev_no <= $rev_no ) {
        my $rev = $svn_repository_reader->get_revision;
        foreach my $path ( @{$rev->changed_paths} ) {
            $reader->change_path( $path );
        }
    }

};

=cut

use Moose;
use Moose::Util::TypeConstraints;
use Carp;
use Readonly;
use List::Util qw( first );
use Unicode::Normalize;


has file                       => ( is => 'ro', isa => 'IO::File', required => 1 );
has client_specific_identifier => ( is => 'ro', isa => 'Str'     , required => 0 );
has fatal_error                => ( is => 'ro', isa => 'CodeRef' , required => 1 );
has warning                    => ( is => 'ro', isa => 'CodeRef' , required => 1 );
has new_revision               => ( is => 'ro', isa => 'CodeRef' , required => 0 );

# A flow list is a hash associating directory/branch/tag names
# with a list of flows that have had that name during the lifetime of the repository:
subtype 'Flows', as 'HashRef[ArrayRef[SVN::BranchingLanguage::DirectoryFlow]]';

has     _active_directories => ( is => 'ro', isa => 'Flows', default => sub { {} } );
has _accessible_branches    => ( is => 'ro', isa => 'Flows', default => sub { {} } );
has _accessible_tags        => ( is => 'ro', isa => 'Flows', default => sub { {} } );

has _previous_revision => ( is => 'rw', isa => 'Int', default => 1 );

has current_section => (
    is      => 'rw',
    isa     => enum([qw[ header body ]]),
    # the current section is publicly readable, but only privately writable:
    writer  => '_status',
    default => 'header',
);


# Revision identifier:
Readonly::Scalar my $REVISION => qr{
    r      # must begin with the letter 'r'
    [1-9]  # the second character must be a non-zero digit
    [0-9]* # any number of digits follow
}x;

# String identifier:
Readonly::Scalar my $DIRECTORY_CHARACTER => qr{
     (?:                # a character within a string can consist of...
         [^\\\r\n"\0/]  # non-escapable characters, except \0 (invalid) and / (path separator)
         |              # or
         \\[\\\r\n"]    # escaped characters
     )
}x;
Readonly::Scalar my $DIRECTORY_ENTRY => qr{
     (?: # A directory entry must begin with
         \.{0,2} (?!\.) $DIRECTORY_CHARACTER # '', '.' or '..', followed by a valid non-dot character
         |                                   # or
         \.{3,}                              # '...'
     )
     # A directory entry must continue with zero or more characters (dots or otherwise):
     $DIRECTORY_CHARACTER*
}x;

Readonly::Scalar my $DIRECTORY => qr{
    " # must begin with a double quote character
    (?: # may be empty,

       # but otherwise must be a valid (escaped) SVN directory name:
       $DIRECTORY_ENTRY (?: /+ $DIRECTORY_ENTRY )* /*

    )?
    " # must end with a double quote character
}x;
Readonly::Scalar my $NAME => qr{
    " # must begin with a double quote character
      # must not be empty,

      # a valid (escaped) name contains one or more:
      (?:
          [^\\\r\n"\0]  # non-escapable characters, except \0 (invalid)
          |             # or
          \\[\\\r\n"]   # escaped characters
      )+

    " # must end with a double quote character
}x;

Readonly::Hash my %UNESCAPE_CHARACTERS => (
    qq{\\} => qq{\\},
      q{"} =>   q{"},
      q{r} => qq{\r},
      q{n} => qq{\n},
);

Readonly::Scalar my $NOT_AN_ACTION => undef;

__PACKAGE__->meta->make_immutable;

#
# FLOW DATA
#
# To check some of the conditions, we need to store information about
# when the flow associated with each name was changed.  We do this
# with a hash:
#
# {
#      add => "revision when added",
#      rm  => "revision when deactivated/deleted",
#      changed => [ "list", "of", "revisions", "when", "changed" ],
# }
#
# Note that the 'changed' array is sorted in decreasing order of
# revision number, because most searches will be looking for one of
# the most-recently-added revisions in the list.

sub check_revision {

    my ( $self, $directory, $revision ) = @_;

    my $flow = $self->_directory_active_in( $directory, $revision );

    unless ($flow) {
        $self->_read_error("Directory '$directory' was not active in r$revision");
        return 0;
    }

    if ( first( sub { $_ == $revision }, @{ $flow->{changed} } ) ) {
        $self->_read_error("Directory '$directory' was not changed in r$revision.");
        return 0;
    }

    return 1;

}

sub _directory_active_in     { return _get_flow( shift->    _active_directories, "deactivated", @_ ); }
sub    _branch_accessible_in { return _get_flow( shift->_accessible_branches   , "deleted"    , @_ ); }
sub       _tag_accessible_in { return _get_flow( shift->_accessible_tags       , "deleted"    , @_ ); }

sub _get_flow {

    my ( $flows, $rm, $name, $revision ) = @_;

    $flows = $flows->{$name};

    return 0 unless $flows;

    # Special case/optimisation to return the currently active flow:
    my $flow = $flows->[-1];
    if ( $revision >= $flow->{added} && !$flow->{$rm} ) {
        return $flow;
    }

    # Return a truthy value if there was an active flow
    # with this name in the specified revision
    foreach my $flow ( @{$flows} ) {
        return $flow if
            $flow->{added} <= $revision &&
            $flow->{$rm  } >  $revision
            ;
    }

    return 0;

}

# get the "from" and "to" revisions for a merge/cherry-pick/revert action,
#
sub _get_real_from_revs {

    my ( $self, $directory, $last, $first ) = @_;

    if ( $first > $last ) {
        $self->_read_error("r$first is greater than r$last");
        return 0;
    }

    my $flow = $self->_get_flow( $self->_active_directories, $directory, $last );
    unless ( $flow ) {
        $self->_read_error(
            "directory '$directory' was not active in r$last\n"
        );
        return 0;
    }

    my $changed = $flow->{changed};

    if ( $first && $changed->{add} > $first ) {
        $self->_read_error(
            "directory '$directory' was not active in r$first,\n" .
            "or was deactivated and reactivated before r$last"
        );
        return 0;
    }

    my $n = $#$changed;
    while ( $n >= 0 && $changed->[$n] > $last ) { --$n }
    $last = $changed->[$n];

    # If the second argument was 0, we can stop now:
    return ( $last, 0 ) unless $first;

    while ( $n >= 0 ) {

        if ( $changed->[$n] == $first ) {
            last;
        }

        if ( $changed->[$n] < $first ) {

            if ( $changed->[ ++$n ] > $last ) {
                $self->_read_error("directory '$directory' was not changed between r$first and r$last");
                return 0;
            }

            last;

        }

        --$n

    }

    return ( $last, $changed->[$n] );

}

=head2 change_directory

    $sbl->change_directory( "trunk", 12 );

Registers that the specified directory changed in the specified revision.

=cut

sub change_directory {

    my ( $self, $directory, $revision ) = @_;

    my $flow = $self->_active_directories->{$directory};

    if ( !$flow ) {
        croak
            "Tried to change $directory in r$revision, but no directory was found with that name.\n" .
            'This is probably a programming error.';
    }

    $flow = $flow->[-1];

    if ( $flow->{deactivated} ) {
        # silently ignore updates on directories that have been deactivated
        return;
    }

    if ( @{ $flow->{changed} } ) {

        if ( $flow->{changed}->[-1] == $revision ) {

            # The directory has already been marked as changing in this revision.
            return;

        } elsif ( $flow->changed_revisions->[-1] > $revision ) {

            croak
                "Tried to change $directory in r$revision, but it has already been changed in " .
                $flow->changed_revisions->[-1] . "\n" .
                'This is probably a programming error.';

        }

    }

    push( @{ $flow->changed_revisions }, $revision );

    return;

}

=head2 change_path

    $sbl->change_path( "trunk/README.txt", 12 );

Registers that all named directories associated with a path changed in the specified revision.

=cut

sub change_path {

    my ( $self, $path, $revision ) = @_;

    my @directories = grep(
        { $_    eq         $path ||
          "$_/" eq substr( $path , 0, length($_)+1 )
        }
        @{$self->_active_directories}
    );

    foreach my $directory (@directories) {
        $self->change_directory( $directory, $revision );
    }

    return;

}

# Wrapper around fatal_error for the most common type of error:
sub _read_error {

    my ( $self, $message ) = @_;

    $self->fatal_error(
        $self->file->input_line_number,
        $message . "\n" .
        'Please correct or remove this line.'
    );

    # fatal_error() should throw an exception, but we support no-throw behaviour too:
    return $NOT_AN_ACTION;

}

# Try to parse out any body action from a line of text, apart from comments (handled below):
sub _get_noncomment_body_action {

    my ( $self, $line ) = @_;

    my $text = $line;

    if ( $line =~ s/^In ($REVISION), //o ) {

        my $rev_no = substr( $1, 1 );

        # It is a fatal error if the next revision is less than the previous one:
        if ( $rev_no < $self->_previous_revision ) {
            return $self->_read_error(
                'This action specifies a revision less than the minimum (' . $self->_previous_revision . ").\n"
            );
        }

        if ( $rev_no > $self->_previous_revision ) {

            $self->_previous_revision($rev_no);

            $self->new_revision($rev_no)
                if $self->new_revision;

        }

        if ( $line =~ s/(create branch|create tag) ($DIRECTORY)//o ) {


            # Create actions

            my $action  = $1;
            my $new_dir = $self->unescape_directory($2);

            my $new_name;
            if ( $line =~ s/ as ($NAME)//o ) {
                $new_name = $self->unescape_name($1);
            } elsif ( $new_dir eq q{} ) {
                return $self->_read_error('You must specify a name when creating the root directory');
            } else {
                $new_name = $new_dir;
            }

            my ( $from, $from_rev );
            if ( $line =~ s/^ from ($DIRECTORY) ($REVISION)$//o ) {
                $from_rev = substr( $2, 1 );
                $from = $self->unescape_directory($1);
            }

            unless ( $line eq q{} ) {
                return $self->_read_error('This is not a valid action.');
            }

            # Check if the directory has already been created:
            if ( $self->_directory_active_in( $new_dir, $rev_no ) ) {
                return $self->_read_error("Directory '$new_dir' was already active in r$rev_no");
            }

            # Check if the name is already accessible:
            if ( $action eq 'create branch' ) {

                if ( $self->_branch_accessible_in( $new_name, $rev_no ) ) {
                    return $self->_read_error("Branch '$new_name' was already accessible in r$rev_no");
                }

            } else {

                if ( $self->_tag_accessible_in( $new_name, $rev_no ) ) {
                    return $self->_read_error("Tag '$new_name' was already accessible in r$rev_no");
                }

            }

            # Check if the 'from' directory exists:
            if ( defined($from) ) {

                if ( $from_rev > $rev_no ) {
                    return $self->_read_error("'From' revision r$from_rev is greater than $rev_no");
                }

                my $from_equals_current = $from_rev == $rev_no;
                ( $from_rev ) = $self->_get_real_from_revs( $from, $from_rev, 0 );
                return $NOT_AN_ACTION unless $from_rev;

                if ( $from_equals_current && $from_rev == $rev_no ) {
                    $self->_read_warning(
                        "Directory '$from' was modified in revision r$from_rev - did you mean r" . ($from_rev-1) . q{?}
                    );
                }

            }

            # we reuse %flow_info to make it easier to update later on:
            my %flow_info = ( add => $rev_no, changed => [$rev_no], );
            push( @{ $self->_active_directories->{$new_dir} }, \%flow_info );
            if ( $action eq 'create branch' ) {
                push( @{ $self->_accessible_branches->{$new_dir} }, \%flow_info );
            } else {
                push( @{ $self->_accessible_tags    ->{$new_dir} }, \%flow_info );
            }

            return {
                text      => $text,
                action    => $action,
                revision  => $rev_no,
                directory => $new_dir,
                name      => $new_name,
                from      => $from,
                from_rev  => $from_rev,
            }


        } elsif ( $line =~ m{(deactivate|delete) ($DIRECTORY)}o ) {

            # Delete actions

            my $action    = $1;
            my $directory = $self->unescape_directory($2);

            my $flow = $self->_get_flow( $self->_active_directories, $directory, $rev_no );

            unless ($flow) {
                return $self->_read_error("Directory '$directory' was not active in r$rev_no");
            }

            $flow->{deactivated} = $rev_no;
            $flow->{deleted    } = $rev_no
                if $action eq 'delete';

            return {
                text      => $text,
                action    => $action,
                revision  => $rev_no,
                directory => $directory,
            }

        } elsif ( $line =~ m{delete (branch|tag) ($NAME)}o ) {

            # Delete actions

            my $type = $1;
            my $name = $self->unescape_name($2);

            my $flow =
                ( $type eq 'branch' )
                ? $self->_get_flow( $self->_accessible_branches, $name, $rev_no )
                : $self->_get_flow( $self->_accessible_tags    , $name, $rev_no )
                ;

            unless ($flow) {
                return $self->_read_error("$type '$name' was not accessible in r$rev_no");
            }

            $flow->{deactivated} ||= $rev_no;
            $flow->{deleted    }   = $rev_no;

            return {
                text     => $text,
                action   => "delete $type",
                revision => $rev_no,
                name     => $name,
            }


        } elsif ( $line =~ m{merge ($DIRECTORY) up to ($REVISION) into ($DIRECTORY)}o ) {

            my ( $from, $last_from_rev, $to ) = ( $1, $2, $3 );

            $from          = $self->unescape_directory($from);
            $last_from_rev = substr( $last_from_rev, 1 );
            $to            = $self->unescape_directory($to  );

            ($last_from_rev) = $self->_get_real_from_revs( $from, $last_from_rev, 0 );
            return $NOT_AN_ACTION unless $last_from_rev;

            return {
                text          => $text,
                action        => 'merge',
                revision      => $rev_no,
                from          => $from,
                last_from_rev => $last_from_rev,
                to            => $to,
            }

        } elsif ( $line =~ m{(cherry-pick) ($DIRECTORY) ($REVISION) into ($DIRECTORY)}o ||
                  $line =~ m{(revert) ($DIRECTORY) ($REVISION) from ($DIRECTORY)}o
            ) {

            my ( $action, $from, $from_rev, $to ) = ( $1, $2, $3, $4 );

            $from     = $self->unescape_directory($from);
            $from_rev = substr( $from_rev, 1 );
            $to       = $self->unescape_directory($to  );

            unless ( $self->_directory_active_in( $to, $rev_no ) ) {
                return $self->_read_error("Directory '$to' was not active in r$rev_no");
            }

            unless ( $self->check_revision( $from, $from_rev ) ) {
                return $NOT_AN_ACTION;
            }

            return {
                text           => $text,
                action         => $action,
                revision       => $rev_no,
                from           => $from,
                first_from_rev => $from_rev,
                 last_from_rev => $from_rev,
                to             => $to,
            }

        } elsif ( $line =~ m{(cherry-pick) ($DIRECTORY) ($REVISION) to ($REVISION) into ($DIRECTORY)}o ||
                  $line =~ m{(revert) ($DIRECTORY) ($REVISION) to ($REVISION) from ($DIRECTORY)}o ) {

            my ( $action, $from, $first_from_rev, $last_from_rev, $to ) = ( $1, $2, $3, $4, $5 );

            $from           = $self->unescape_directory($from);
            $first_from_rev = substr( $first_from_rev, 1 );
             $last_from_rev = substr(  $last_from_rev, 1 );
            $to             = $self->unescape_directory($to  );

            if ( $first_from_rev > $last_from_rev ) {
                return $self->_read_error("'From' revision r$first_from_rev is greater than $last_from_rev");
            }

            ( $last_from_rev, $first_from_rev ) = $self->_get_real_from_revs( $from, $last_from_rev, $first_from_rev );
            return $NOT_AN_ACTION unless $last_from_rev;

            return {
                text           => $text,
                action         => $action,
                revision       => $rev_no,
                from           => $from,
                first_from_rev => $first_from_rev,
                 last_from_rev =>  $last_from_rev,
                to             => $to,
            }


        } elsif ( $line =~ m{ignore ($DIRECTORY)}o ) {

            my ($directory) = ($1);

            $directory = $self->unescape_directory($directory);

            unless ( $self->check_revision( $directory, $rev_no ) ) {
                return $NOT_AN_ACTION;
            }

            return {
                text      => $text,
                action    => 'ignore',
                revision  => $rev_no,
                directory => $directory,
            }

        } elsif ( $line =~ m{amend ($DIRECTORY), keeping (.*)}o ) {

            my ( $directory, $keep ) = ( $1, $2 );

            $directory = $self->unescape_directory($directory);

            if    ( $keep eq 'the new log message' ) { $keep = 'new' }
            elsif ( $keep eq 'the old log message' ) { $keep = 'old' }
            elsif ( $keep eq 'both log messages'   ) { $keep = 'both' }
            else {
                return $self->_read_error('This is not a valid action.');
            }

            unless ( $self->check_revision( $directory, $rev_no ) ) {
                return $NOT_AN_ACTION;
            }

            return {
                text      => $text,
                action    => 'amend',
                revision  => $rev_no,
                directory => $directory,
                keep      => $keep,
            }

        }

    }

    return $self->_read_error('This is not a valid action.');

}

# Comments are handled (almost) identically in the header/body sections:
sub _get_comment {

    my ( $self, $line ) = @_;

    if ( $line =~ /^#/ ) {

        # Lines beginning with a '#' must be treated as comments.
        # Clients are discouraged from commenting actions with
        # '#', so we don't check for commented-out actions.

        return { action => 'comment', text => $line }

    } elsif ( $line =~ /^;\s*(.*)/ ) {

        # Lines beginning with a ';' must be treated as comments.
        # Clients are encouraged to comment actions with ';',
        # so we check for commented-out actions.

        my $commented_action = $1;

        if ( $self->current_section ne 'header' ) {

            # for simplicity of implementation, we only suggest
            # private actions in the header.

            my $client_specific_identifier =
                defined($self->client_specific_identifier)
                ? quotemeta($self->client_specific_identifier)
                : '(?!)' # no-match string
                ;

            if ( $commented_action =~ /^\($client_specific_identifier (.*)\)$/ ) {
                $commented_action = {
                    action => 'private action',
                    text   => $commented_action,
                    value  => $1,
                };
            }

        } else {

            # check for all commented actions in the body

            $commented_action = $self->_get_noncomment_body_action($commented_action);
            if ($commented_action) {
                return { action => 'comment', text => $1, commented_action => $commented_action };
            } else {
                # no valid action found (should have used a '#' comment instead!)
                return { action => 'comment', text => $line };
            }

        }

    } elsif ( $line =~ /^\s*$/ ) {

        # This is an empty line - for convenience, we consider
        # this a type of comment.

        return { action => 'comment', text => $line }

    }

    # this does not look like a comment
    return $NOT_AN_ACTION;

}

=head2 get_header

    my $actions = $sbl->get_header();

Read the header, and return an arrayref of actions.  Example return value:

[
    { action => 'comment'                    , text => '#!/usr/bin/my-great-parser',                            },
    { action => 'version identifier'         , text => 'This is a version 0.1 SVN Branching Language file',     },
    { action => 'private action'             , text => '(another-parser will write debug info to 'debug.log'),  },
    { action => 'private action'             , text => '(my-great-parser will write debug info to 'debug.log'),
      value => "will write debug info to 'debug.log'", },
    },
    { action => 'header-body boundary marker', text => 'Body:',                                                 }
]

=cut

sub get_header {

    my $self = shift;

    if ( $self->current_section ne 'header' ) {

        $self->fatal_error(
            $self->file->input_line_number,
            "There can only be a single header section, at the start of the file.\n" .
            'The header section has already been parsed.'
        );
        # in case we are passed a fatal_error() that doesn't die:
        return [];

    }

    my $file = $self->file;

    my $client_specific_identifier =
        defined( $self->client_specific_identifier )
        ? quotemeta( $self->client_specific_identifier )
        : '(?!)' # no-match string
        ;

    my @actions;

    my $version_identifier_seen = 0;

    while (<$file>) {

        my $line = $_;

        # This parser accepts any type of newline marker:
        $line =~ s/(?:\r\n|\n|\r)//;

        my $comment_action = $self->_get_comment($line);

        if ($comment_action) {

            # Comments can appear anywhere, even before the version identifier
            push( @actions, $comment_action );

        } elsif ( $line eq 'This is a version 0.1 SVN Branching Language file' ) {

            # The version idintifier should occur exactly once,
            # as the first (non-comment) action in the file.

            push( @actions, { action => 'version identifier', text => $line, } );

            if ($version_identifier_seen) {

                $self->fatal_error(
                    $file->input_line_number,
                    'Please remove this duplicate version number.'
                );
                # in case we are passed a fatal_error() that doesn't die:
                return [];

            }

        } elsif ( !$version_identifier_seen ) {

            # Only comment actions are allowed before the version identifier.

            $self->fatal_error(
                $file->input_line_number,
                "The file does not begin with a valid version identifier\n" .
                'Please make sure this is a version 0.1 SVN Branching Language file.'
            );
            return [];

        } elsif ( $line eq 'Body:' ) {

            # The header-body boundary marker indicates we have now
            # reached the end of the header.

            push( @actions, { action => 'header-body boundary marker', text => $line } );

            $self->current_section('body');

            return \@actions;                                               # RETURN HERE

        } elsif ( $line =~ /^\((.*)\)$/ ) {

            my $private_action = $1;

            if ( $private_action =~ s/^$client_specific_identifier // ) {
                push( @actions, { action => 'private action', text => $line, value => $private_action, } );
            } else {
                push( @actions, { action => 'private action', text => $line, } );
            }

        }

    }


    $self->fatal_error(
        $file->input_line_number,
        "The file ended in the middle of the header.\n" .
        'Please check the file is complete.'
    );

    # in case we are passed a fatal_error() that doesn't die:
    return [];

}

=head2 unescape_string

    my $unescape_stringd_string = $sbl->unescape_string('"trunk"');

Convert an escaped string to its unescape_stringd value.

=cut

sub unescape_string {

    my ( $self, $str ) = @_;

    $str =~ s/\\([\\\r\n"])/$UNESCAPE_CHARACTERS{$1}/ge;

    return $str;

}

sub unescape_name { return shift->unescape_string(@_) }

sub unescape_directory {

    my ( $self, $str ) = @_;

    $str = $self->unescape_string($str);

    # canonical decomposition:
    $str = NFD($str);

    # Collapse strings of '/' characters down to a single '/':
    $str =~ s{/+}{/}g;

    # Remove the trailing '/' character:
    $str =~ s{/$}{};

    return $str;

}

=head2 get_body_action

    my $body_action = $self->get_body_action;

Read the next line in the body, and return an action.  Example return values:

{ text => '# file was created Mon Mar 12 10:15:00 GMT 2012',
  action => 'comment'
}

{ text => 'In r1, create branch "trunk"'
  action => 'create branch', revision => 1, directory => 'trunk', name => 'trunk', from => undef, from_rev => undef
}

{ text => 'In r10, create branch "branches/v1" as "v1" from "trunk" r10'
  action => 'create branch', revision => 10, directory => 'branches/v1', name => 'v1', from => 'trunk', from_rev => 9
}

{ text => 'In r11, create tag "tags/v1" as "v1" from "branches/v1" r10'
  action => 'create tag', revision => 11, directory => 'tags/v1', name => 'v1', from => 'branches/v1', from_rev => 10
}

{ text => 'In r20, delete "tags/v1"'
  action => 'delete', revision => 20, directory => 'tags/v1'
}

{ text => 'In r20, deactivate "tags/v1"'
  action => 'deactivate', revision => 20, directory => 'tags/v1'
}

{ text => 'In r20, delete tag "v1"'
  action => 'delete tag', revision => 20, name => 'v1'
}

{ text => 'In r25, merge "trunk" r24 into "branches/v1"',
  action => 'merge', revision => 25, from => 'trunk', last_from_rev => 24, to => 'branches/v1'
}

{ text => 'In r30, cherry-pick "trunk" r27 into "branches/v1"',
  action => 'cherry-pick', revision => 30, from => 'trunk', first_from_rev => 27, last_from_rev => 27, to => 'branches/v1'
}

{ text => 'In r31, cherry-pick "trunk" r28 to r30 into "branches/v1"',
  action => 'cherry-pick', revision => 31, from => 'trunk', first_from_rev => 28, last_from_rev => 29, to => 'branches/v1'
}

{ text => 'In r32, revert "trunk" r27 from "branches/v1"',
  action => 'revert', revision => 32, from => 'trunk', first_from_rev => 27, last_from_rev => 27, to => 'branches/v1'
}

{ text => 'In r33, revert "trunk" r28 to r30 from "branches/v1"',
  action => 'revert', revision => 33, from => 'trunk', first_from_rev => 28, last_from_rev => 29, to => 'branches/v1'
}

{ text => 'In r40, ignore "trunk"'
  action => 'ignore', revision => 40, directory => 'trunk',
}

{ text => 'In r40, amend "trunk", keeping the old log message'
  action => 'amend', revision => 40, directory => 'trunk', keep => 'old',
}

{ text => 'In r40, amend "trunk", keeping the new log message'
  action => 'amend', revision => 40, directory => 'trunk', keep => 'new',
}

{ text => 'In r40, amend "trunk", keeping both log messages'
  action => 'amend', revision => 40, directory => 'trunk', keep => 'both',
}

{ action => 'comment", text => '; In r25, merge "trunk" r24 into "branches/v1"',
  commented_action => { action => 'merge', revision => 25, from => 'trunk', last_from_rev => 24, to => 'branches/v1' }
}

=cut

sub get_body_action {

    my ($self) = @_;

    my $line = $self->file->getline;

    # End of file:
    return $NOT_AN_ACTION unless defined $line;

    # This parser accepts any type of newline marker:
    $line =~ s/(?:\r\n|\n|\r)//;

    my $comment_action = $self->_get_comment($line);

    if ($comment_action) {

        return $comment_action;

    } else {

        return $self->_get_noncomment_body_action($line);

    }

}

=head2 get_body

    my $body = $self->get_body;

Convenience wrapper around get_body_action(), to retrieve all actions at once.

=cut

sub get_body {

    my ($self) = @_;

    my @actions;

    while ( my $line = $self->get_body_action ) {
        push( @actions, $line );
    }

    return \@actions;

}

no Moose;
no Moose::Util::TypeConstraints;

1;
