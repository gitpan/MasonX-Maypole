package MasonX::Maypole;
use warnings;
use strict;
use Carp;

use Maypole 2;
use Apache::MVC 2;

use base 'Apache::MVC';

Maypole::Config->mk_accessors( 'masonx' );

__PACKAGE__->mk_classdata( 'mason_ah' );

use Maypole::Constants;

=head1 NAME

MasonX::Maypole - use Mason as the frontend and view for Maypole version 2

=head1 VERSION

Version 0.02

=cut

our $VERSION = '0.2_01';

=head1 SYNOPSIS

    package BeerDB;
    use warnings;
    use strict;

    use Class::DBI::Loader::Relationship;

    use MasonX::Maypole 0.2;
    use base 'MasonX::Maypole';

    BeerDB->setup( 'dbi:mysql:beerdb' );

    BeerDB->config->{view}           = 'MasonX::Maypole::View';
    BeerDB->config->{template_root}  = '/var/www/beerdb';
    BeerDB->config->{uri_base}       = '/beerdb';
    BeerDB->config->{rows_per_page}  = 10;
    BeerDB->config->{display_tables} = [ qw( beer brewery pub style ) ];

    BeerDB->config->masonx->{comp_root}  = [ factory => '/var/www/maypole/factory' ];
    BeerDB->config->masonx->{data_dir}   = '/path/to/mason/data_dir';
    BeerDB->config->masonx->{in_package} = 'My::Mason::App';

    BeerDB::Brewery->untaint_columns( printable => [qw/name notes url/] );

    BeerDB::Style->untaint_columns( printable => [qw/name notes/] );

    BeerDB::Beer->untaint_columns(
        printable => [qw/abv name price notes/],
        integer => [qw/style brewery score/],
        date => [ qw/date/],
    );

    BeerDB->config->{loader}->relationship($_) for (
        "a brewery produces beers",
        "a style defines beers",
        "a pub has beers on handpumps");

    1;

=head1 DEVELOPER RELEASE

This release is fundamentally different from previous MasonX::Maypole releases,
and B<will break sites> that are using them. Previous releases did not work
with Maypole 2. This and future releases will not work with Maypole 1.

=head1 DESCRIPTION

A frontend and view for Maypole 2, using Mason.

=head1 CONFIGURING MASON

Set any parameters for the Mason ApacheHandler in C<My::Maypole::App->config->{masonx}>.
This is where to tell Maypole/Mason where the factory templates are stored.

=head1 TEMPLATES

This distribution includes Masonized versions of the standard Maypole templates,
plus a dhandler and autohandler. The autohandler simply takes care of adding
a header and footer to every page.

The dhandler is responsible for implementing
part of the Maypole template lookup behaviour. It first looks for a template
specific to the table being queried by the request. If no such template is
found, it defers the lookup to Mason's component search path. This is set
in C<init>. The result is that the lookup follows the same
sequence as described in the Maypole documentation (table > site > factory).
You can add extra component roots if you need them.

So if you set the factory comp_root to point at the Maypole factory templates,
the thing should Just Work right out of the box.

=head1 METHODS

=over

=item init

This method is called by Maypole during startup. Sets up the Mason
ApacheHandler.

=cut

# This only gets called once. Mason's path searching mechanism replaces
# get_template_root and Maypole::View::Base::paths.
sub init {
    my ( $class ) = @_;

    warn "initialising $class" if $class->debug;

    my $config    = $class->config;
    my $mason_cfg = $config->masonx;

    warn( "starting Mason config: " . YAML::Dump( $mason_cfg ) )
        if $class->debug;

    my $template_root = $config->template_root ||
        die 'must specify template_root in config';

    my $comp_roots = $mason_cfg->{comp_root} || [];

    my $factory;
CROOT:  foreach my $index ( 0 .. $#$comp_roots )
    {
        if ( $comp_roots->[ $index ][0] eq 'factory' )
        {
            $factory = delete $comp_roots->[ $index ];
            last CROOT;
        }
    }

    push @$comp_roots, [ tables  => File::Spec->catdir( $template_root, 'tables' ) ];
    push @$comp_roots, [ custom  => File::Spec->catdir( $template_root, 'custom' ) ];
    push @$comp_roots, [ maypole => $template_root ];
    push @$comp_roots, [ factory => $factory->[1] || File::Spec->catdir( $template_root, 'factory' ) ];

    $mason_cfg->{comp_root} = $comp_roots;

    $mason_cfg->{decline_dirs} = 0                       unless $mason_cfg->{decline_dirs};
    $mason_cfg->{in_package}   = 'HTML::Mason::Commands' unless $mason_cfg->{in_package};

    warn( "final Mason config: " . YAML::Dump( $mason_cfg ) ) if $class->debug;

    $class->mason_ah( MasonX::Maypole::ApacheHandler->new( %{ $mason_cfg } ) );

    $class->SUPER::init;
}

=item parse_args

Uses Mason to extract the request arguments from the request.

=cut

# override the method in Apache::MVC
sub parse_args {
    my ( $self ) = @_;

    # set and return request args in Mason request object
    my $args = $self->mason_ah->request_args( $self->ar );

    $self->{params} = $args;
    $self->{query}  = $args;
}

=item send_output

Template variables have already been exported to Mason components namespace
in C<MasonX::Maypole::View::template>. This method now runs the Mason Cexec>
phase to generate and send output.

=cut

sub send_output {
    my ( $self ) = @_;

    # if there was an error, there may already be a report in the output slot,
    # so send it via Apache::MVC
    $self->SUPER::send_output if $self->output;

    my $m = eval { $self->mason_ah->prepare_request( $self->ar ) };

    if ( my $error = $@ )
    {
        $self->output( $error );
        $self->SUPER::send_output;

        # In here, $m is actually a status code, but Maypole::handler isn't
        # interested so no point in returning it.
        return;
    }

    $self->ar->content_type(
          $self->content_type =~ m/^text/
        ? $self->content_type . "; charset=" . $self->document_encoding
        : $self->content_type
    );

    # now generate output
    $m->exec;
}


{
    # copied from MasonX::WebApp
    package MasonX::Maypole::ApacheHandler;
    use base 'HTML::Mason::ApacheHandler';

    sub request_args
    {
        my ( $self, $apr ) = @_;

        return $apr->pnotes('__request_args__') if $apr->pnotes('__request_args__');

        my $args = ($self->SUPER::request_args($apr))[0] || {};

        $apr->pnotes( __request_args__ => $args );

        return $args;
    }
}

=back

=head1 AUTHOR

David Baird, C<< <cpan@riverside-cms.co.uk> >>

=head1 TODO

Currently hard-coded to use Apache/mod_perl. Shouldn't be too hard to use CGI
instead.

=head1 BUGS

Please report any bugs or feature requests to
C<bug-masonx-maypole2@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.  I will be notified, and then you'll automatically
be notified of progress on your bug as I make changes.

=head1 TESTS

There are none. The module loads Mason::ApacheHandler, which causes compile
time errors unless loaded within mod_perl.

=head1 ACKNOWLEDGEMENTS

=head1 COPYRIGHT & LICENSE

Copyright 2004 David Baird, All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of MasonX::Maypole2
