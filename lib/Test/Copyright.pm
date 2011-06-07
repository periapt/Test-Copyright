package Test::Copyright;

use warnings;
use strict;
use Carp;
use 5.008;

use Test::Builder;
use Test::More;
use CPAN::Meta;
use Software::LicenseUtils;
use Readonly;
use Perl6::Slurp;
use UNIVERSAL::require;

use version; our $VERSION = '0.1';

# Module implementation here

Readonly my @META_FILES => ('META.yml','META.json');
Readonly my @LICENSE_FILES => ('LICENSE','COPYING','README',);
Readonly my $DUMMY_COPYRIGHT => 'XYZ';

my $Test = Test::Builder->new;
my %copyright_data = ();

sub import {
    my $self = shift;
    my $caller = caller;

    for my $func ( qw( copyright_ok) ) {
        no strict 'refs'; ## no critic
        *{$caller."::".$func} = \&$func;
    }

    $Test->exported_to($caller);
    $Test->plan(@_);
}

sub copyright_ok {
    my $name = @_ ? shift : "Copyright test";
    my $meta = cpan_meta_ok();
    if ($meta) {
        my @classes = Software::LicenseUtils->guess_license_from_meta($meta);
        $Test->ok(length @classes > 0, "more than zero licenses");
        my @licenses = software_licenses_ok(@classes);
        $Test->ok(length @licenses > 0, "more than zero recognized licenses");
        my $assumed_copyright_statement = license_file_ok(@licenses);
    }
    else {
        $Test->skip('No CPAN::Meta object', 3);
    }

    return;
}

sub software_licenses_ok {
    my @classes = @_;
    my $all_valid = 1;
    my @licenses;
    foreach my $class (@classes) {
        if (defined $class) {
            if ($class->require) {
                my $license = $class->new({holder=>$DUMMY_COPYRIGHT});
                if ($license and $license->isa($class)) {
                    push @licenses, $license;
                }
                else {
                    $all_valid = 0;
                }
            }
            else {
                $all_valid = 0;
            }
        }
        else {
            $all_valid = 0;
        }
    }
    $Test->ok($all_valid, 'Found a bad license object');
    return @licenses;
}

sub cpan_meta_ok {
    foreach my $file (@META_FILES) {
        if (-r $file) {
            my $meta = CPAN::Meta->load_file($file);
            return if not isa_ok($meta, 'CPAN::Meta', 'found CPAN::Meta file');
            return slurp $file;
        }
    }
    $Test->ok(0, 'found CPAN::Meta file');
    return;
}

sub license_file_ok {
    my @licenses = @_;
    my $found_file = undef;
    foreach my $file (@LICENSE_FILES) {
        if (-r $file) {
            $found_file = slurp $file;
            $Test->diag("found license file: $file");
            last;
        }
    }
    $Test->ok($found_file, 'found license file');
    if ($found_file) {
        foreach my $license (@licenses) {
            $found_file = verify_license($found_file, $license);
        }
    }
    return $found_file;
}

sub verify_license {
    my $file_contents = shift;
    my $license = shift;
    my $holder = $license->holder;
    my $year = $license->year;
    my $dummy_copyright = "This software is copyright (c) $year by $holder.\n";
    my $full_text = _purge_dummy($license->fulltext, $dummy_copyright);

    pass;
    return $file_contents;
}

sub _purge_dummy {
    my $text = shift;
    my $dummy_copyright = shift;
    croak "Cannot find dummy copyright: ".substr($text, 0, 100) 
        if $dummy_copyright ne substr($text, 0, length $dummy_copyright);
    return substr($text, 1+length $dummy_copyright);
}

1; # Magic true value required at end of module
__END__

=head1 NAME

Test::Copyright - Test that a module has good license information

=head1 VERSION

This document describes Test::Copyright version 0.1

=head1 SYNOPSIS

    use Test::Copyright;

=head1 DESCRIPTION

This module attempts to check the quality of a module from the copyright
and open source license perspectives. The following tests are applied

=over

=item The license and authors are determined using L<CPAN::Meta>.

=item The README file is required to contain the copyright and license
statement generated from L<Software::License>.

=item The README file is also parsed for exceptions.

=item Each file is checked for consistency against this spec.

=back

=head1 INTERFACE 

=head2 copyright_ok

This method does all the tests described above.

=head2 cpan_meta_ok

This method checks for the existence of a valid C<META.yml> or
C<META.json> file and returns the text as a scalar.

=head2 software_licenses_ok

This method takes a list of class names, which should be in the
L<Software::License> namespace, and returns the corresponding
instantiated objects with a dummy copyright holder. It also passes
a test if and only if all the classes could be so instantiated.

=head2 license_file_ok

This method takes a list of L<Software::License> objects, looks
for a LICENSE, COPYING or README file and checks that that file
contains all the corresponding license statements. It returns
the remainder of the text.

=head1 DIAGNOSTICS

=for author to fill in:
    List every single error and warning message that the module can
    generate (even the ones that will "never happen"), with a full
    explanation of each problem, one or more likely causes, and any
    suggested remedies.

=over

=item C<< Error message here, perhaps with %s placeholders >>

[Description of error here]

=item C<< Another error message here >>

[Description of error here]

[Et cetera, et cetera]

=back


=head1 CONFIGURATION AND ENVIRONMENT

=for author to fill in:
    A full explanation of any configuration system(s) used by the
    module, including the names and locations of any configuration
    files, and the meaning of any environment variables or properties
    that can be set. These descriptions must also include details of any
    configuration language used.
  
Test::Copyright requires no configuration files or environment variables.


=head1 DEPENDENCIES

=for author to fill in:
    A list of all the other modules that this module relies upon,
    including any restrictions on versions, and an indication whether
    the module is part of the standard Perl distribution, part of the
    module's distribution, or must be installed separately. ]

None.


=head1 INCOMPATIBILITIES

=for author to fill in:
    A list of any modules that this module cannot be used in conjunction
    with. This may be due to name conflicts in the interface, or
    competition for system or program resources, or due to internal
    limitations of Perl (for example, many modules that use source code
    filters are mutually incompatible).

None reported.


=head1 BUGS AND LIMITATIONS

=for author to fill in:
    A list of known problems with the module, together with some
    indication Whether they are likely to be fixed in an upcoming
    release. Also a list of restrictions on the features the module
    does provide: data types that cannot be handled, performance issues
    and the circumstances in which they may arise, practical
    limitations on the size of data sets, special cases that are not
    (yet) handled, etc.

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-test-copyright@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.

=head1 ACKNOWLEDGEMENTS

I have to express my gratitude to (or possibly annoyance with) ingydotnet
for provoking me into writing this module.

=head1 AUTHOR

Nicholas Bamber  C<< <nicholas@periapt.co.uk> >>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2011, Nicholas Bamber C<< <nicholas@periapt.co.uk> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
