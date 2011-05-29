use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Test::Copyright',
    license             => 'perl',
    dist_author         => 'Nicholas Bamber <nicholas@periapt.co.uk>',
    dist_version_from   => 'lib/Test/Copyright.pm',
    build_requires => {
        'Test::More' => 0,
    },
    requires => {
        'version'       => 0,
        'CPAN::Meta'    => 0,
        'Software::LicenseUtils' => 0,
        'Perl6::Slurp'  => 0,
        'Readonly'      => 0,
        'UNIVERSAL::require' => 0,
    },
    configure_requires => {
        'Module::Build' => '0.38',
    },   
    create_readme=>1,
    create_makefile_pl => 'traditional',
    add_to_cleanup      => [ 'Test-Copyright-*' ],
);

$builder->create_build_script();
