package MasonX::Maypole;
use strict;
use warnings;
 
use base 'Maypole';

use Maypole::Constants; 
use HTML::Mason::Request;

our $VERSION = '0.04';

=head1 NAME

MasonX::Maypole - provide a Mason frontend to Maypole

=head1 SYNOPSIS

In your Maypole driver class:

    package BeerDB;
    use base 'MasonX::Maypole';
    BeerDB->setup( 'dbi:mysql:beerdb' );
    BeerDB->config->{ view } = 'Maypole::View::Base';

    # ... rest of BeerDB driver configuration
    
    1;
    
In beerdb/autohandler:
    
    % %ARGS = ( %ARGS, BeerDB->vars );
    <h1><a href="/<% $ARGS{ base } %>">Beer Database</a></h1>
    <& /navbar, %ARGS &>
    % $m->call_next( %ARGS );
    
In beerdb/dhandler:
    
    <& '/' . $ARGS{ request }->{ template }, %ARGS &>
    
In the Mason handler.pl script:

    # loading BeerDB.pm could instead go in the autohandler,
    # or else in httpd.conf (PerlModule BeerDB)
    use BeerDB; 
    
    my $ah = HTML::Mason::ApacheHandler->new(
                comp_root => [ [ main    => $main_comp_root ], # for the rest of your website
                               [ beerdb  => '/path/to/beerdb' ],
                               [ factory => '/path/to/maypole/factory/templates' ],
                               # ... maybe some others, whatever you already have
                               ],
                ...
                
                # continue along
                
=cut

=begin comment

=head1 ABSTRACT

This module removes most of the 'view' processing from the Maypole request
cycle, leaving all that to Mason. 

=cut

=end comment

=head1 DESCRIPTION

This module removes most of the 'view' processing from the Maypole request
cycle, leaving all that to Mason. 

=cut

=head2 Templates

The templates provided are XHTMLized, Mason-ized versions of the
standard Maypole factory templates. A basic CSS file is included.

The C<link> template has been renamed C<mplink> because you may already have a
utility component called C<link> in a shared component root. Well, at any rate,
I do.

=over 4

=item template variables

The L<Maypole::View::TT> way of working is to inject the template variables
into the namespace of each template. For Mason users, this would be similar to
defining the variables as request globals, and you could do that if you prefer.
However, for simplicity, in the setup shown above the template variables are
retrieved by the root autohandler and placed in the %ARGS hash. This means that
the template vars have to be passed around manually between components.

Mason doesn't differentiate between URL args (i.e. the query) and POSTed
content. Query parameters and POSTed data can be accessed directly in the
Mason components. This is different from standard Maypole, where query
arguments are stored in the Maypole request (C<$request->{query}>)
and POSTed arguments are available in C<$request->{params}>.

So in the Mason templates, you can access submitted data directly by name, via
%ARGS, or via the Maypole template variables which are added to %ARGS in the
autohandler. These include the Maypole request, so finally you can get at the
submitted data through C<$ARGS{ request }->{ params }> (or C<$request->{ params }>
if you specify C<$request> in the Mason C<%args> block). C<$request->{ query }>
will always be empty. 

=item template paths

The Mason configuration shown above gives a variation on the template search path
behaviour used in the standard Maypole setup. If a table-specific template -
C</path/to/beerdb/[table]/[template]> exists, that will be used. Otherwise, a
database-specific template C</path/to/beerdb/[template]> will be used, if it
exists. Finally, the generic factory template in
C</path/to/maypole/factory/templates> is used. You are free to place them
anywhere else you prefer, and to add more search paths if appropriate (or
remove them). 

All templates are placed in the same directory, since there is no difference
in Mason between a template and a macro. They're all components. But really
that's up to you.

=back

=cut

=head2 Methods

=over 4

=item prepare_request

This method replaces C<Maypole::handler> (and C<Maypole::handler_guts>) as the
workflow controller that coordinates the various tasks carried out during a
Maypole request. Basically, the output phase of the Maypole request has been
removed (and is delegated to Mason).

Returns the Maypole request object.

You will not normally need to call this directly - see the C<vars> method. 

NOTE

For requests to unknown tables or actions, this method currently removes the
C<base_url> portion of the path and sets the template slot of the Maypole
request object to the remaining path. That path is then used in the dhandler
to start the Mason search of component roots for a suitable component.

Whether this is the Right Thing to do will depend on how you have set up the
Mason component roots. I think. Frankly, this bit confuses me, but seems to
work for the setup described above.

So don't rely on this behaviour in future releases, it may change if someone
can explain to me how this stuff should really work. 

=cut

sub prepare_request {
    my $class = shift;
    
    $class->init unless $class->init_done;
    
    my $r = bless { config => $class->config }, $class;
    
    # this stores the apr object
    $r->get_request;
    
    # this extracts all the data from the HTTP request and URL
    $r->parse_location;
    
    # the rest mostly from Maypole::handler_guts
    $r->model_class( $r->config->{model}->class_of($r, $r->{table}) );

    # check if table and action exist and are callable
    my $status = $r->is_applicable;
    
    # check if allowed
    if ($status == OK) { 
        $status = $r->call_authenticate;
        
        if ($r->debug and $status != OK and $status != DECLINED) {
            $r->view_object->error($r,
                "Got unexpected status $status from calling authentication" );
        }
        
        return $status unless $status == OK;
        
        $r->additional_data;
    
        $r->model_class->process( $r );
    }
    else { # probably DECLINED
        # Otherwise, it's just a plain template.
        delete $r->{ model_class };
        
        # this is different from Maypole.pm, and depends on setting up the
        # base dir of the Maypole app as a Mason component root
        my $base = $r->{ config }->{ uri_base };

        $r->{path} =~ s/^$base//;
       
        $r->template( $r->{ path } );
    }
    
    # At this point, everything is set up in the Maypole request object,
    # but no content has been generated, and template variables have not
    # been set up and passed to the Mason components. That will happen
    # in the app root autohandler, instead of in the template method
    # of the view base class
    return $r;    
}

=item vars

Calls C<prepare_request> and extracts and returns the template variables.

=cut

sub vars { 
    my $class = shift;
    
    # run everything
    my $r = $class->prepare_request;
    
    # collect the data
    $r->view_object->vars( $r );
}

=item parse_path

Used by C<parse_location> to extract things from the URL.

This implements a URL structure. If you prefer a different structure, override
this method in your Maypole driver. You will also need to edit the C<mplink>
factory template and various other bits (mostly form action parameters) in
other templates. See L<Maypole::Request>.

The structure used here is C<[uri_base]/[table]/[action]/[arg].html> or
C<[uri_base]/[table]/[action].html>. Typically C<arg> will be an integer ID.

=cut

sub parse_path {
    my $self = shift;
    
    $self->{ path } ||= 'index.html';
    
    my $path = $self->{ path };
    
    my $base = $self->config->{ uri_base };
    
    $path =~ s/^$base\///;
    
    my @pi = split /\//, $path;
    
    $self->{ table }  = shift @pi;
    
    my $action = shift @pi;
    $action =~ s/\.html$//;
    $self->{ action } = $action;
    
    # $arg should be an id, where relevant
    my $arg = shift @pi;
    $arg =~ s/\.html$//;
        
    $self->{ args } = [ $arg ];
}

=item get_request

Stores the C<Apache::Request> in the Maypole request object. 

=cut

sub get_request { $_[0]->{ar} = Apache::Request->instance(Apache->request) }

=item parse_location

Mason has already extracted any form data and URL queries and combined them
into a single set of parameters. This method retrieves that data, plus data
encoded in the URL (extracted with C<parse_path>) and stores it in the Maypole
request. 

=cut

sub parse_location {
    my $self = shift;

    $self->{path} = $self->{ar}->uri;

    my $loc = $self->{ar}->location;

    no warnings 'uninitialized';

    $self->{path} =~ s/^($loc)?\///;

    $self->parse_path;
    
    my $m = HTML::Mason::Request->instance;
    
    $self->{params} = { $m->request_args };

    while (my ($key, $value) = each %{$self->{params}}) {
        $self->{params}{$key} = '' unless defined $value;
    }
    
    $self->{query}  = {}; # { $self->{ar}->args };
}

=back

=cut

# we don't need the get_template_root and send_output methods from Apache::MVC

1;

=head1 DEPENDENCIES

Mason and Maypole.

L<HTML::Element> is used in the C<search> template, but is not a dependency of
L<MasonX::Maypole> per se. 

=head1 BUGS

Please report all bugs via the CPAN Request Tracker at
L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=MasonX-Maypole>.

=head1 COPYRIGHT AND LICENSE

Copyright 2004 by David Baird.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

David Baird, C<cpan@riverside-cms.co.uk>

Most of the code comes from L<Maypole> and L<Apache::MVC>, by Simon Cozens.

=head1 SEE ALSO

L<Apache::MVC>, L<Maypole::View::Mason>.

=cut
