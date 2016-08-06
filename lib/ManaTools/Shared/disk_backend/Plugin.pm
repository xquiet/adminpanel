# vim: set et ts=4 sw=4:
package ManaTools::Shared::disk_backend::Plugin;

#============================================================= -*-perl-*-

=head1 NAME

    ManaTools::Shared::disk_backend::Plugin - disks object

=head1 SYNOPSIS

    package ManaTools::Shared::disk_backend::Plugin::Foo;
    use Moose;

    extend 'ManaTools::Shared::disk_backend::Plugin';

    override('load', sub {
        ...
    });

    override('save', sub {
        ...
    });

    override('probe', sub {
        ...
    });

    1;

    package ManaTools::Shared::disk_backend::Part::Baz;
    use Moose;

    extend 'ManaTools::Shared::disk_backend::Part';

    has '+type', default => 'baz';
    has '+restrictions', default => sub { ... };

    ...

    1;

=head1 DESCRIPTION

    This plugin is a abstract plugin for the backend to manadisk

=head1 SUPPORT

    You can find documentation for this plugin with the perldoc command:

    perldoc ManaTools::Shared::disk_backend::Plugin


=head1 AUTHOR

    Maarten Vanraes <alien@rmail.be>

=head1 COPYRIGHT and LICENSE

Copyright (c) 2015 Maarten Vanraes <alien@rmail.be>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License version 2, as
published by the Free Software Foundation.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=head1 METHODS

=cut

use Moose;

use ManaTools::Shared::RunProgram;

## class DATA
has 'dependencies' => (
    is => 'ro',
    init_arg => undef,
    isa => 'ArrayRef[Str]',
    lazy => 1,
    default => sub {
        return [];
    },
);

has 'tools' => (
    traits => ['Hash'],
    is => 'ro',
    isa => 'HashRef[Str]',
    default => sub { return {}; },
    init_arg => undef,
    handles => {
        tool => 'get',
    },
);

has 'parent' => (
    is => 'ro',
    isa => 'ManaTools::Shared::disk_backend',
    required => 1,
    handles => ['D','I','W','E'],
);

#=============================================================

=head2 load

=head3 OUTPUT

    0 if failed, 1 if success

=head3 DESCRIPTION

    this is a default method for loading Part's, the idea is to override it if needed

=cut

#=============================================================
sub load {
    my $self = shift;

    1;
}

#=============================================================

=head2 save

=head3 OUTPUT

    0 if failed, 1 if success

=head3 DESCRIPTION

    this is a default method for saving Part's, the idea is to override it if needed

=cut

#=============================================================
sub save {
    my $self = shift;

    1;
}

#=============================================================

=head2 probe

=head3 OUTPUT

    0 if failed, 1 if success

=head3 DESCRIPTION

    this is a default method for probing Part's, the idea is to override it if needed

=cut

#=============================================================
sub probe {
    my $self = shift;

    1;
}

#=============================================================

=head2 changedpart

=head3 INPUT

    $part: ManaTools::Shared::disk_backend::Part
    $state: PartState (L, P, S)

=head3 DESCRIPTION

    this is a default method for announcing a changed Part, the idea is to override it if needed

=cut

#=============================================================
sub changedpart {
    my $self = shift;
    my $part = shift;
    my $state = shift;

    1;
}

#=============================================================

=head2 savepart

=head3 INPUT

    $part: ManaTools::Shared::disk_backend::Part

=head3 OUTPUT

    0 if failed, 1 if success

=head3 DESCRIPTION

    this is a default method for saving a specific Part, the idea is to override it if needed

=cut

#=============================================================
sub savepart {
    my $self = shift;
    my $part = shift;

    1;
}

#=============================================================

=head2 tool_exec

=head3 INPUT

    $toolname: Str
    @args: Array[Str]

=head3 OUTPUT

    Int: exitcode

=head3 DESCRIPTION

    this is a method for executing a tool and getting only the exit code

=cut

#=============================================================
sub tool_exec {
    my $self = shift;
    my $toolname = shift;
    my @args = @_;
    my $tool = $self->tool($toolname);
    # exit early if tool doesn't exit
    return undef if (!defined($tool) || !$tool);

    # insert tool before @args
    unshift @args, $self->tool($toolname);

    # get lines
    return ManaTools::Shared::RunProgram::raw({exitcode => 1}, @args);
}

#=============================================================

=head2 tool_lines

=head3 INPUT

    $toolname: Str
    @args: Array[Str]

=head3 OUTPUT

    Array[Str]

=head3 DESCRIPTION

    this is a default method for executing a tool and getting all the STDOUT
    lines in an ARRAY

=cut

#=============================================================
sub tool_lines {
    my $self = shift;
    my $toolname = shift;
    my @args = @_;
    my $tool = $self->tool($toolname);
    # exit early if tool doesn't exit
    return undef if (!defined($tool) || !$tool);

    # insert tool before @args
    unshift @args, $self->tool($toolname);

    # get lines
    return ManaTools::Shared::RunProgram::get_stdout(join(' ', @args). ' 2>/dev/null');
}

#=============================================================

=head2 tool_fields

=head3 INPUT

    $toolname: Str
    $separator: Str
    @args: Array[Str]

=head3 OUTPUT

    0 if failed, 1 if success

=head3 DESCRIPTION

    this is a default method for executing a tool and getting all the STDOUT
    in a HASH depending on the separator

=cut

#=============================================================
sub tool_fields {
    my $self = shift;
    my $toolname = shift;
    my $separator = shift;
    my @args = @_;
    my %fields = ();

    # get lines from tool
    my @lines = $self->tool_lines($toolname, @args);
    for my $line (@lines) {

        # split into key & value
        my @value = split($separator, $line);

        # if not key & value, next line
        next if (scalar(@value) < 2);

        my $key = shift(@value);
        my $value = join($separator, @value);

        # trim key & value
        $key =~ s/^\s+//;
        $key =~ s/\s+$//;
        $value =~ s/^\s+//;
        $value =~ s/\s+$//;

        # assign into fields
        $fields{$key} = $value if ($key ne '');
    }
    return %fields;
}

#=============================================================

=head2 tool_columns

=head3 INPUT

    $toolname: Str
    $headers: Bool
    $ignores: Int
    $identifier: Int
    $separator: Str
    @args: Array[Str]

=head3 OUTPUT

    HashRef[HashRef]|undef

=head3 DESCRIPTION

    this is a default method for executing a tool and getting all the STDOUT
    in a HASH depending on the separator when it's a column-based output

=cut

#=============================================================
sub tool_columns {
    my $self = shift;
    my $toolname = shift;
    my $headers = shift;
    my $ignores = shift;
    my $identifier = shift;
    my $separator = shift;
    my @args = @_;
    my $fields = {};

    # get lines from tool
    my @lines = $self->tool_lines($toolname, @args);
    return $fields if scalar(@lines) < ($ignores + !!$headers);
    my @headers = ();
    # get headers
    my $line = shift(@lines);
    @headers = split($separator, $line) if $headers;
    # ignore lines if needed
    for (my $i = 0; $i < $ignores; $i = $i + 1) {
        shift(@lines);
    }
    # loop the data
    for my $line (@lines) {
        my $item = {};

        # split into key & value
        my @value = split($separator, $line);

        # if no 2 columns, skip this line
        next if (scalar(@value) < 2);

        my $i = 0;
        for my $value (@value) {
            my $key = $i;
            $key = $headers[$i] if (defined $headers[$i]);

            # trim key & value
            $key =~ s/^\s+//;
            $key =~ s/\s+$//;
            $value =~ s/^\s+//;
            $value =~ s/\s+$//;

            # need to be the index if key is empty after all
            $key = $i if ($key eq '');

            # set the field
            $item->{$key} = $value;

            # next field
            $i = $i + 1;
        }
        $fields->{$item->{$identifier}} = $item if defined($item->{$identifier});
    }
    return $fields;
}

1;
