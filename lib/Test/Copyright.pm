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
use Lingua::EN::NameParse;
use Email::Address;
use File::Spec;

our $VERSION = '0.0_1';

# Module implementation here

my $nameparse = Lingua::EN::NameParse->new;

Readonly my $DEFAULT => '';
Readonly my @META_FILES => ('META.yml','META.json');
Readonly my @LICENSE_FILES => ('LICENSE','COPYING','README');
Readonly my $DUMMY_COPYRIGHT => 'XYZ';
Readonly my %LICENSE_SPECIALS => (
    perl => [
        # This string is generated by Module::Starter::PBP by default.
        'This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself. See perlartistic.',
    ],
);

# This line draws inspiration from licensecheck.
# (C) 2007-2008, Adam D. Barratt
Readonly my $COPYRIGHT_REGEX =>
    qr{
        ^                       # Beginning of line
        \#?                     # Can be commented out
        \s*                     # Arbitrary amount of space
	(?:
            [Cc]opyright	# The full word
            |[Cc]opr\.          # Legally-valid abbreviation
	    |\x{00a9}           # Unicode character COPYRIGHT SIGN
	    |\xc2\xa9	        # Unicode copyright sign encoded in iso8859
	    |\([Cc]\)           # Legally-null representation of sign
	    |Copyright\s+\([Cc]\)  # Generated by Module::Starter::PBP
	)
        \:?                     # Optional colon
        \s+                     # Space
        (?:(\d{4})-)?           # Optional initial year
        (\d{4})                 # Actual year
        \,?\s+                  # Comma and space
        ([^\n\r]+)              # Copyright holder
        $
    }xms;

# This list was copied from Test::Pod.
# Copyright 2006-2010, Andy Lester. Some Rights Reserved.
Readonly my %IGNORE_DIRS => (
    '.bzr' => 'Bazaar',
    '.git' => 'Git',
    '.hg'  => 'Mercurial',
    '.pc'  => 'quilt',
    '.svn' => 'Subversion',
    CVS    => 'CVS',
    RCS    => 'RCS',
    SCCS   => 'SCCS',
    _darcs => 'darcs',
    _sgbak => 'Vault/Fortress',
);

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
    my $meta = _cpan_meta_ok();
    if ($meta) {
        my @classes = Software::LicenseUtils->guess_license_from_meta($meta);
        $Test->ok(length @classes > 0, "more than zero licenses");
        my @licenses = _software_licenses_ok(@classes);
        $Test->ok(length @licenses > 0, "more than zero recognized licenses");
        my $license_file_contents = _license_file_ok(@licenses);
        my $copyright_details = undef;
        if ($license_file_contents) {
            $copyright_details = _parse_copyright($license_file_contents);
            foreach my $file (_find_files_to_check()) {
                _check_file_for_copyright($file, $copyright_details);
            }
        }
        else {
            fail('Parse copyright details');
        }
    }
    else {
        $Test->skip('No CPAN::Meta object', 3);
    }

    return;
}

sub _software_licenses_ok {
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
    $Test->ok($all_valid, 'Found a good license object');
    return @licenses;
}

sub _cpan_meta_ok {
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

sub _license_file_ok {
    my @licenses = @_;
    my $found_file = undef;
    my $file_name = undef;
    foreach my $file (@LICENSE_FILES) {
        if (-r $file) {
            $found_file = slurp $file;
            $file_name = $file;
            last;
        }
    }
    $Test->ok($found_file, "found license file: $file_name");
    if ($found_file) {
        foreach my $license (@licenses) {
            $found_file = _verify_license($found_file, $license, $file_name);
        }
    }
    return $found_file;
}

sub _verify_license {
    my $file_contents = shift;
    my $license = shift;
    my $file_name = shift;
    my $holder = $license->holder;
    my $year = $license->year;
    my $meta = $license->meta_name;
    my $test_name = "Found license $meta in file $file_name";
    my $dummy_copyright = "This software is copyright (c) $year by $holder.\n";
    my $full_text = _purge_dummy($license->fulltext, $dummy_copyright);
    my $notice = _purge_dummy($license->notice, $dummy_copyright);
    my $remainder = _remove_license($file_contents, $full_text);
    my @specials =  @{$LICENSE_SPECIALS{$meta}};
    if ($remainder) {
        $file_contents = $remainder;
        pass($test_name);
    }
    elsif ($remainder = _remove_license($file_contents, $notice)) {
        $file_contents = $remainder;
        pass($test_name);
    }
    elsif (grep {$remainder = _remove_license($file_contents, $_)} @specials) {
        $file_contents = $remainder;
        pass($test_name);
    }
    else {
        fail($test_name);
    }
    return $file_contents;
}

sub _purge_dummy {
    my $text = shift;
    my $dummy_copyright = shift;
    croak "Cannot find dummy copyright: ".substr($text, 0, 100) 
        if $dummy_copyright ne substr($text, 0, length $dummy_copyright);
    return substr($text, 1+length $dummy_copyright);
}

sub _remove_license {
    my $file_contents = shift;
    my $license_text = shift;
    $license_text
        =~ s{
            ([\\\!\"\$\%\^\&\*\(\)\-\_\=\+\{\[\]\}\#\~\;\-\'\@\,\<\.\>\/\?])
        }{\\$1}xmsg;
    $license_text
        =~ s{
            (\s+)
        }{\\s+}xmsg;
    my $remainder = undef;
    if ($file_contents =~ m{\A(.*)$license_text(.*)\z}xms) {
        $remainder = "$1$2";
    }
    return $remainder;
}

sub _parse_copyright {
    my $license_file_contents = shift;
    my @lines = split /\n/, $license_file_contents;
    my $copyright = undef;
    foreach my $line (@lines) {
        if (my $detail = _parse_copyright_line($line)) {
            diag "(C) $detail->{initial_year}-$detail->{final_year}, $detail->{holder}";
            $copyright = _push_copyright($copyright, $DEFAULT, $detail)
            # TODO pick details for individual files
        }
    }
    ok(exists $copyright->{$DEFAULT}, "Found default copyright details");
    return $copyright;
}

sub _push_copyright {
    my $copyright = shift;
    my $file = shift;
    my $detail = shift;
    my $holder = delete $detail->{holder};
    if (not defined $copyright) {
        $copyright = {};
    }
    if (exists $copyright->{$file}) {
        $copyright->{$file}->{$holder} = $detail;
    }
    else {
        $copyright->{$file} = {$holder=>$detail};
    }
    return $copyright;
}

sub _parse_copyright_line {
    my $line = shift;
    my $details = undef;
    if ($line =~ $COPYRIGHT_REGEX) {
        $details = {};
        $details->{final_year} = $2;
        $details->{initial_year} = $1 || $details->{final_year};
        $nameparse->parse($3);
        my %properties = $nameparse->properties;
        $details->{holder} = $nameparse->case_all;
        if ($properties{non_matching}
            =~ m{\<($Email::Address::addr_spec)\>}xms) {
            $details->{holder} .= " <$1>";
        }
    }
    return $details;
}

sub _check_file_for_copyright {
    my $file = shift;
    my $copyright = shift;
    my $file_contents = slurp $file;
    my @lines = split /\n/, $file_contents;
    my $file_has_copyright = 0;
    my $all_copyright_known = 1;
    foreach my $line (@lines) {
        if (my $detail = _parse_copyright_line($line)) {
            $all_copyright_known
               &&= _check_copyright_details($file, $detail, $copyright);
            $file_has_copyright = 1;
        }
    }
    ok($file_has_copyright, "File $file has copyright statement");
    ok($all_copyright_known, "Copyright for $file is described centrally");
    return;
}

sub _check_copyright_details {
    my $file = shift;
    my $detail = shift;
    my $copyright = shift;
    my $holder = $detail->{holder};
    if (not exists $copyright->{$DEFAULT}->{$holder}) {
        diag "Unlisted copyright holder: $holder [$file]";
        return 0;
    }
    my $years = $copyright->{$DEFAULT}->{$holder};
    if ($detail->{initial_year} < $years->{initial_year}) {
        diag "Year mismatch: ($detail->{initial_year}, $holder) [$file]";
        return 0;
    }
    if ($detail->{final_year} > $years->{final_year}) {
        diag "Year mismatch: ($detail->{final_year}, $holder) [$file]";
        return 0;
    }
    return 1;
}

# This function is copied from Test::Pod.
sub _find_files_to_check {
    my @queue = @_ ? @_ : _starting_points();
    my @pod = ();

    while ( @queue ) {
        my $file = shift @queue;
        if ( -d $file ) {
            local *DH;
            opendir DH, $file or next;
            my @newfiles = readdir DH;
            closedir DH;

            @newfiles = File::Spec->no_upwards( @newfiles );
            @newfiles = grep { not exists $IGNORE_DIRS{ $_ } } @newfiles;

            foreach my $newfile (@newfiles) {
                my $filename = File::Spec->catfile( $file, $newfile );
                if ( -f $filename ) {
                    push @queue, $filename;
                }
                else {
                    push @queue, File::Spec->catdir( $file, $newfile );
                }
            }
        }
        if ( -f $file ) {
            push @pod, $file if _is_perl( $file );
        }
    } # while
    return @pod;
}

sub _starting_points {
    return 'blib' if -e 'blib';
    return 'lib';
}

sub _is_perl {
    my $file = shift;

    return 1 if $file =~ /\.PL$/;
    return 1 if $file =~ /\.p(?:l|m|od)$/;
    return 1 if $file =~ /\.t$/;

    open my $fh, '<', $file or return;
    my $first = <$fh>;
    close $fh;

    return 1 if defined $first && ($first =~ /(?:^#!.*perl)|--\*-Perl-\*--/);

    return;
}


1; # Magic true value required at end of module
__END__

=head1 NAME

Test::Copyright - Test that a module has good license information

=head1 VERSION

This document describes Test::Copyright version 0.0_1

=head1 SYNOPSIS

    use Test::Copyright;

=head1 DESCRIPTION

This module attempts to check the quality of a module from the copyright
and open source license perspectives. The following tests are applied:

=over

=item That a L<CPAN::Meta> object can be read from the source.

=item That the said L<CPAN::Meta> object contains at least one license.

=item That the said L<CPAN::Meta> object contains at least one license
recognized by L<Software::License>.

=item That we can read at least one of LICENSE, COPYING or README.

=item That the said LICENSE/COPYING/README file contains either the notice
or the full text (as generated by L<Software::License>) for every
license listed by the L<CPAN::Meta> object. The matching process
is forgiving over space and for certain licenses alternative texts may be tried.

=item That the said LICENSE/COPYRIGHT/README file (after excluding the
license texts) contains at least one copyright statement that can 
be inferred to be the default copyright statement for the whole package.

=item That the said default copyright statement has at least one final year 
that matches the current year. [TODO]

=item That every perl file has at least one copyright statement.

=item That every copyright statement in every perl file is consistent
with the centralized copyright information.

=back

=head1 INTERFACE 

=head2 copyright_ok

This function does all the tests described above.

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
Copyright (c) 2007-2008, Adam D. Barratt [portions]
Copyright (c) 2006-2010, Andy Lester [portions]

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
