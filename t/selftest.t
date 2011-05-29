#!perl 

use Test::More tests=>6;

BEGIN {
    use_ok( "Test::Copyright" );
}

my $self = $INC{'Test/Copyright.pm'};

copyright_ok($self, "My own copyright is OK");

