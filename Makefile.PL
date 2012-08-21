use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'EDAMSync',
    AUTHOR        => 'ninjinkun <>',
    VERSION_FROM  => 'lib/EDAMSync.pm',
    PREREQ_PM     => {
        'Amon2'                           => '3.52',
        'Text::Xslate'                    => '1.5006',
        'Test::More'                      => '0.98',
        'Amon2::DBI'                      => '0.06',
        'DBD::SQLite'                     => '1.33',
        'HTML::FillInForm::Lite'          => '1.09',
        'JSON'                            => '2.50',
        'Plack::Middleware::ReverseProxy' => '0.09',
        'Plack::Middleware::Session'      => '0',
        'Plack::Session'                  => '0.14',
        'Test::WWW::Mechanize::PSGI'      => '0',
        'Time::Piece'                     => '1.20',
        'DateTime'                        => '0.72',
        'DateTime::Format::MySQL'         => '0.04',
        'Data::UUID'                      => '1.218',
        'SQL::Interp'                     => '1.21',
        'List::MoreUtils'                 => '0.33',
    },
    MIN_PERL_VERSION => '5.008001',
    (-d 'xt' and $ENV{AUTOMATED_TESTING} || $ENV{RELEASE_TESTING}) ? (
        test => {
            TESTS => 't/*.t xt/*.t',
        },
    ) : (),
);
