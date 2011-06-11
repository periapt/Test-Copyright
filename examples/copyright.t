use strict;
use warnings;
use English qw(-no_match_vars);
use Test::More;

if ( not $ENV{TEST_AUTHOR} ) {
    my $msg = 'Author test.  Set $ENV{TEST_AUTHOR} to a true value to run.';
    plan( skip_all => $msg );
}

eval { require Test::Copyright; };

if ( $EVAL_ERROR ) {
   my $msg = 'Test::Copyright required to verify copyright';
   plan( skip_all => $msg );
}

Test::Copyright::copyright_ok();
