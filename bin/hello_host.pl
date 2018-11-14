#!/usr/bin/env perl

use strict;
use warnings;

use Sys::Hostname;

my $hostname = hostname();

print "Hello $hostname!\n";
