# -*- perl -*-
# Lintian::Data -- interface to query lists of keywords

# Copyright (C) 2008 Russ Allbery
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 2 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along with
# this program.  If not, see <http://www.gnu.org/licenses/>.

package Lintian::Data;
use strict;
use warnings;

use Carp qw(croak);

sub new {
    my ($class, @args) = @_;
    my $type = $args[0];
    my $self = {};
    my $data;
    croak 'no data type specified' unless $type;
    bless $self, $class;
    $data = $self->_get_data ($type);
    if ($data) {
        # We already loaded this data file - just pull from cache
        $self->{'data'} = $data;
    } else {
        # Pretend we loaded this data file, but leave a "reminder" to
        # do it later.
        $self->{'promise'} = \@args;
    }
    return $self;
}

# _get_data fetches an already loaded dataset by type.  It is
# mostly useful for determining whether it makes sense to make
# sense to be "lazy".
#
# _load_data loads a dataset into %data, which is private to this
# module.  Use %data as a cache to avoid loading the same dataset more
# than once (which means lintian doesn't support having the list
# change over the life of the process).  The returned object knows
# what dataset, stored in %data, it is supposed to act on.
{
    my %data;
    sub _get_data {
        my ($self, $type) = @_;
        return $data{$type};
    }
    sub _load_data {
        my ($self, $type, $separator, $code) = @_;
        unless (exists $data{$type}) {
            my $dir = $ENV{LINTIAN_ROOT} . '/data';
            open(my $fd, '<', "$dir/$type")
                or croak("unknown data type $type");
            local ($_, $.);
            while (<$fd>) {
                chomp;
                s/^\s+//;
                next if /^\#/;
                next if $_ eq '';
                my ($key, $val);
                if (defined $separator) {
                    ($key, $val) = split(/$separator/, $_, 2);
                    if ($code) {
                        my $pval = $data{$type}{$key};
                        $val = $code->($key, $val, $pval);
                        next if ! defined $val && defined $pval;
                        unless (defined $val) {
                            next if defined $pval;
                            croak "undefined value for $key (type: $type)";
                        }
                    }
                } else {
                    ($key, $val) = ($_ => 1);
                }
                $data{$type}{$key} = $val;
            }
            close $fd;
        }
        $self->{'data'} = $data{$type};
     }
}

sub _force_promise {
    my ($self) = @_;
    my $promise = $self->{promise};
    $self->_load_data (@$promise);
    delete $self->{promise}
}

# Query a data object for whether a particular keyword is valid.
sub known {
    my ($self, $keyword) = @_;
    $self->_force_promise unless exists $self->{data};
    return (exists $self->{data}{$keyword}) ? 1 : undef;
}

# Return all known keywords (in no particular order).
sub all {
    my ($self) = @_;
    $self->_force_promise unless exists $self->{data};
    return keys(%{ $self->{data} });
}

# Query a data object for the value attached to a particular keyword.
sub value {
    my ($self, $keyword) = @_;
    $self->_force_promise unless exists $self->{data};
    return (exists $self->{data}{$keyword}) ? $self->{data}{$keyword} : undef;
}

1;

=head1 NAME

Lintian::Data - Lintian interface to query lists of keywords

=head1 SYNOPSIS

    my $keyword;
    my $list = Lintian::Data->new('type');
    if ($list->known($keyword)) {
        # do something ...
    }
    my $hash = Lintian::Data->new('another-type', '\s+');
    if ($list->value($keyword) > 1) {
        # do something ...
    }
    my @keywords = $list->all;

=head1 DESCRIPTION

Lintian::Data provides a way of loading a list of keywords or key/value
pairs from a file in the Lintian root and then querying that list.
The lists are stored in the F<data> directory of the Lintian root and
consist of one keyword or key/value pair per line.  Blank lines and
lines beginning with C<#> are ignored.  Leading and trailing whitespace
is stripped.

If requested, the lines are split into key/value pairs with a given
separator regular expression.  Otherwise, keywords are taken verbatim
as they are listed in the file and may include spaces.

This module allows lists such as menu sections, doc-base sections,
obsolete packages, package fields, and so forth to be stored in simple,
easily editable files.

NB: By default Lintian::Data is lazy and defers loading of the data
file until it is actually needed.

=head2 Interface for the CODE argument

This section describes the interface between for the CODE argument
for the class method new.

The sub will be called once for each key/pair with three arguments,
KEY, VALUE and CURVALUE.  The first two are the key/value pair parsed
from the data file and CURVALUE is current value assoicated with the
key.  CURVALUE will be C<undef> the first time the sub is called with
that KEY argument.

The sub can then modify VALUE in some way and return the new value for
that KEY.  If CURVALUE is not C<undef>, the sub may return C<undef> to
indicate that the current value should still be used.  It is not
permissible for the sub to return C<undef> if CURVALUE is C<undef>.

Where Perl semantics allow it, the sub can modify CURVALUE and the
changes will be reflected in the result.  As an example, if CURVALUE
is a hashref, new keys can be inserted etc.

=head1 CLASS METHODS

=over 4

=item new(TYPE [,SEPARATOR[, CODE]])

Creates a new Lintian::Data object for the given TYPE.  TYPE is a partial
path relative to the F<data> directory and should correspond to a file in
that directory.  The contents of that file will be loaded into memory and
returned as part of the newly created object.  On error, new() throws an
exception.

If SEPARATOR is given, it will be used as a regular expression for splitting
the lines into key/value pairs.

If CODE is also given, it is assumed to be a sub that will pre-process
the key/value pairs.  See the L</Interface for the CODE argument> above.

A given file will only be loaded once.  If new() is called again with the
same TYPE argument, the data previously loaded will be reused, avoiding
multiple file reads.

=back

=head1 INSTANCE METHODS

=over 4

=item all()

Returns all keywords listed in the data file as a list (in no particular
order; the original order is not preserved).  In a scalar context, returns
the number of keywords.

=item known(KEYWORD)

Returns true if KEYWORD was listed in the data file represented by this
Lintian::Data instance and false otherwise.

=item value(KEYWORD)

Returns the value attached to KEYWORD if it was listed in the data
file represented by this Lintian::Data instance and the undefined value
otherwise. If SEPARATOR was not given, the value will '1'.

=back

=head1 DIAGNOSTICS

=over 4

=item no data type specified

new() was called without a TYPE argument.

=item unknown data type %s

The TYPE argument to new() did not correspond to a file in the F<data>
directory of the Lintian root.

=item undefined value for %s (type: %s)

The CODE argument return undef for the KEY and no previous value for
that KEY was available.

=back

=head1 FILES

=over 4

=item LINTIAN_ROOT/data

The files loaded by this module must be located in this directory.
Relative paths containing a C</> are permitted, so files may be organized
in subdirectories in this directory.

=back

=head1 ENVIRONMENT

=over 4

=item LINTIAN_ROOT

This variable must be set to Lintian's root directory (normally
F</usr/share/lintian> when Lintian is installed as a Debian package).  The
B<lintian> program normally takes care of doing this.  This module doesn't
care about the contents of this directory other than expecting the F<data>
subdirectory of this directory to contain its files.

=back

=head1 AUTHOR

Originally written by Russ Allbery <rra@debian.org> for Lintian.

=head1 SEE ALSO

lintian(1)

=cut

1;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et
