#!/usr/bin/env perl

use strict;
use warnings;

use Cwd qw/abs_path cwd getcwd/;
use File::Basename;
use Test::More;

BEGIN {
    my $abs_path = dirname( dirname ( abs_path( $0 ) ) );
    push @INC, $abs_path . "/lib";
}

use_ok( "Necromancer" );

my $necro = Necromancer->new();

is( ref $necro, "Necromancer", "Created necro object" );



done_testing();
