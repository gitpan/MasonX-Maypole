package MasonX::Maypole::View;
use warnings;
use strict;

use Maypole::Constants;
use Memoize;
use Symbol 'qualify_to_ref';

use base 'Maypole::View::Base';

=head1 NAME

MasonX::Maypole::View - Mason view subclass for MasonX::Maypole + Maypole 2

=head1 SYNOPSIS

See L<MasonX::Maypole|MasonX::Maypole>.

=head1 METHODS

=over

=item template

Loads the Maypole template vars into Mason components' namespace.

=cut

sub template 
{
    my ( $self, $r ) = @_;
    
    my $pkg = $r->config->masonx->{in_package};

    my %vars = $self->vars( $r );

    warn __PACKAGE__ . " - template vars maybe not getting cleaned up" if $r->debug > 1;
    
    foreach my $varname ( keys %vars )
    {
        my $export = qualify_to_ref( $varname, $pkg );
        *$export = \$vars{ $varname };

        # this does _not_ seem to be cleaning up always?
        $r->ar->register_cleanup( sub { undef *$export; 1 } );
    }

    return OK;
}

=item paths

Builds the list of component roots in the correct order for Mason to search:

    table-specific      - if path exists
    custom              - if path exists
    template root
    factory 

=cut

memoize( 'paths', NORMALIZER => sub { shift; shift->model_class || '__no_model__' } );

# this returns config info, so should be in the controller
sub paths 
{
    my ( $self, $r ) = @_;
    
    return $r->_paths;
}

1;

