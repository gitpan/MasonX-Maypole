package MasonX::Maypole;
use warnings;
use strict;
use Carp;

use HTML::Mason 1.30; # for dynamic comp roots
use Maypole 2.10;     # for Maypole::Application support

# need to get rid of this, and a couple of bits and pieces, to allow CGI mode
use base 'Apache::MVC';

our $VERSION = 0.51;

Maypole::Config->mk_accessors( qw( masonx factory_root ) );

__PACKAGE__->mk_classdata( 'mason_ah' );

=head1 NAME

MasonX::Maypole - use Mason as the frontend and view for Maypole version 2

=head1 SYNOPSIS

    package BeerDB;
    use warnings;
    use strict;

    use Class::DBI::Loader::Relationship;

    use Maypole::Application qw( -Debug2 MasonX AutoUntaint );

    BeerDB->setup( 'dbi:mysql:beerdb', 'username', 'password' );

    BeerDB->config->{template_root}  = '/home/beerdb/www/www/htdocs';
    BeerDB->config->{uri_base}       = '/';
    BeerDB->config->{rows_per_page}  = 10;
    BeerDB->config->{display_tables} = [ qw( beer brewery pub style ) ];
    BeerDB->config->{application_name} = 'The Beer Database';

    BeerDB->config->masonx->{comp_root}  = [ [ factory => '/var/www/maypole/factory' ] ];
    BeerDB->config->masonx->{data_dir}   = '/home/beerdb/www/www/mdata';
    BeerDB->config->masonx->{in_package} = 'BeerDB::TestApp';

    BeerDB->auto_untaint;

    BeerDB->config->{loader}->relationship($_) for (
        'a brewery produces beers',
        'a style defines beers',
        'a pub has beers on handpumps',
        );

    1;

=head1 ** API CHANGES **

Version 0.5 contains major modifications, and changes to error handling. See 
the Changes file for details.

=head1 DESCRIPTION

A frontend and view for Maypole, using Mason.

=head1 EXAMPLES

Example C<BeerDB.pm> and a C<httpd.conf> VirtualHost setup are included in 
the C</doc> directory of the distribution.

A working example of the BeerDB application is at C<http://beerdb.riverside-cms.co.uk>, 
including the C<BeerDB.pm> and C<httpd.conf> used for that site.

=head1 CONFIGURING MASON

Set any parameters for the Mason ApacheHandler in C<<BeerDB->config->{masonx}>>.
This is where to tell Maypole/Mason where the factory templates are stored.

Note that the user the server runs as must have permission to read the files in the
factory templates directory, which also means all directories in the path to the
templates must be readable and executable (i.e. openable). If Mason can't read
these templates, you may get a cryptic 'file doesn't exist' error, but you
will not get a 'not permitted' error.

=head1 Maypole::Application

L<Maypole::Application|Maypole::Application> needs to be patched before it will work 
with MasonX::Maypole. You can download a patched copy from C<http://beerdb.riverside-cms.co.uk>, 
until the required updates are included in the version distributed with L<Maypole>.

=head1 TEMPLATES

This distribution includes Masonized versions of the standard Maypole templates,
plus a dhandler and autohandler. The autohandler simply takes care of adding
a header and footer to every page, while the dhandler loads the template
specified in the Maypole request object.

So if you set the factory comp_root to point at the Maypole factory templates,
the thing should Just Work right out of the box. Except for maypole.css, which 
you will need to copy to the right place on your server. 

=head1 METHODS

=over

=item init

This method is called by Maypole while processing the first request the server
receives. Probably better under mod_perl to call this explicitly at the end of
your setup code (C<BeerDB-E<gt>init>) to share memory among Apache children.
Sets up the Mason ApacheHandler, including the search path behaviour.

=cut

# This only gets called once. Mason's path searching mechanism replaces
# get_template_root and Maypole::View::Base::paths.
sub init 
{
    my ( $r ) = @_;

    my $mason_cfg = $r->config->masonx;
    
    $mason_cfg->{comp_root} = [ $r->_paths ];
    
    $mason_cfg->{decline_dirs} ||= 0;
    $mason_cfg->{in_package}   ||= 'HTML::Mason::Commands';
    $mason_cfg->{dynamic_comp_root} = 1;
    
    $r->mason_ah( MasonX::Maypole::ApacheHandler->new( %{ $mason_cfg } ) );
    
    $r->config->view || $r->config->view( 'MasonX::Maypole::View' );
        
    # set up the view object
    $r->SUPER::init;
}

# MasonX::Maypole::View::path() wraps this
sub _paths
{
    my ( $r ) = @_; # class during startup, object during requests

    my $root    = $r->config->template_root || $r->get_template_root;
    my $factory = $r->config->factory_root; 
    
    $root = ref $root eq 'ARRAY' ? $root : [ $root ];
    
    my @paths;

    foreach my $path ( @$root ) 
    {
        if ( ref $r ) # false during startup - calling model_class() is a fatal error
        {
            if ( my $model = $r->model_class )
            {
                my $model_path = File::Spec->catdir( $path, $model->moniker );
                
                $model =~ s/::/_/g;
                
                push @paths, [ $model, $model_path ] if -d $model_path;
            }
        }
                
        my $custom = File::Spec->catdir( $path, 'custom'  );
        
        push @paths, [ custom => $custom ] if -d $custom;
        
        push @paths, [ default => $path ];
        
        my $this_factory = File::Spec->catdir( $path, 'factory' );
        push @paths, [ factory => $this_factory ] if -d $this_factory;
    }
    
    push @paths, [ factory => $factory ] if $factory;
    
    return @paths;
}

=item parse_args

Uses Mason to extract the request arguments from the request.

=cut

# override the method in Apache::MVC
sub parse_args 
{
    my ( $r ) = @_;

    # set and return request args in Mason request object
    my $args = $r->mason_ah->request_args( $r->ar );

    $r->{params} = $args;
    $r->{query}  = $args;
}

=item send_output

Template variables have already been exported to Mason components namespace
in C<MasonX::Maypole::View::template>. This method now runs the Mason C<exec>
phase to generate and send output.

=cut

sub send_output 
{
    my ( $r ) = @_;
    
    #
    # set up the Mason request object
    #
    
    # if there was an error, there may already be a report in the output slot
    die $r->output if $r->output;

    my $m = $r->mason_ah->prepare_request( $r->ar );
    
    unless ( ref $m )
    {
        warn "prepare_request returned this: [$m] instead of a Mason request object";
        return $m;
    }
    
    #
    # set headers (Mason will set content-length and call send_http_header)
    #
    $r->ar->content_type(
          $r->content_type =~ m/^text/
        ? $r->content_type . "; charset=" . $r->document_encoding
        : $r->content_type
    );
    
    foreach ( $r->headers_out->field_names ) 
    {
        next if /^Content-(Type|Length)/;
        $r->{ar}->headers_out->set( $_ => $r->headers_out->get( $_ ) );
    }
    
    #
    # set dynamic comp roots
    #
    $m->interp->comp_root( [ $r->view_object->paths( $r ) ] );

    if ( $r->debug > 1 )
    {
        Data::Dumper->require or die "Failed to load Data::Dumper: $@";
        warn "Comp roots: " . Data::Dumper::Dumper( $m->interp->comp_root );
    }
    
    # now generate and send output
    my $status = $m->exec;
    
    # Maypole doesn't actually check this status, but for the sake of good form:
    return $status;
}

=item get_template_root

Returns C<template_root> from the config.

This varies from L<Apache::MVC|Apache::MVC>, which concatenates
document_root and location from the Apache request server config.

=cut

sub get_template_root { $_[0]->config->template_root }

=item get_request

Replaces C<Apache::MVC::get_request>, using C<Apache::Request::instance()> instead 
of C<Apache::Request::new()> to obtain the APR object. Calling C<new> means Mason 
and Maypole have different APR objects, and the Mason one doesn't have any POST 
data.

=cut

sub get_request 
{
    my ( $self, $r ) = @_;
    
    $self->{ar} = Apache::Request->instance( $r ); 
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
