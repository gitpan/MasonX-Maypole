package BeerDB;
use warnings;
use strict;

use Class::DBI::Loader::Relationship;

use MasonX::Maypole 0.216;
use base 'MasonX::Maypole';

BeerDB->setup( 'dbi:mysql:BeerDB', 
               'beerdbuser',
               'password',
               );

BeerDB->config->{view}           = 'MasonX::Maypole::View';
BeerDB->config->{template_root}  = '/usr/home/dave/www/beerdb/htdocs/beerdb';
BeerDB->config->{uri_base}       = '/beerdb';
BeerDB->config->{rows_per_page}  = 10;
BeerDB->config->{display_tables} = [ qw( beer brewery pub style ) ];

BeerDB->config->masonx->{comp_root}  = [ [ factory => '/usr/local/www/maypole/factory' ] ];
BeerDB->config->masonx->{data_dir}   = '/usr/home/dave/www/beerdb/mdata/maypole';
BeerDB->config->masonx->{in_package} = 'BeerDB::TestApp';

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
