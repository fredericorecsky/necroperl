#!/usr/bin/env perl

use strict;
use warnings;

use Cwd qw/abs_path cwd getcwd/;
use File::Basename;
use Test::More;

my $abs_path;

BEGIN {
    $abs_path = dirname( dirname ( abs_path( $0 ) ) );
    push @INC, $abs_path . "/lib";
}

my $bin_dir = $abs_path . "/bin";
opendir( my $dh, "$bin_dir" );

my @files = readdir( $dh );

for my $file ( @files ) {
    next if $file =~ /^\.{1,2}$/;
    my $file_path = "$bin_dir/$file";
    diag $file_path;
    open my $fh, "<" , $file_path;
    my $shebang = <$fh>;
    close $fh;
    diag $shebang;
    next if $shebang !~ /perl/;
    system ( "perl -c $bin_dir/$file" );
    is( $?, 0 , "File compiles" );
}



done_testing();
