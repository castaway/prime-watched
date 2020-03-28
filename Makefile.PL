use ExtUtils::MakeMaker::CPANfile;
 
WriteMakefile(
    NAME             => 'Prime::Watched',
    VERSION_FROM     => 'lib/Prime/Watched.pm',
    ABSTRACT_FROM    => 'lib/Prime/Watched.pm',
    AUTHOR           => ['Jess Robinson <JROBINSON@cpan.org>'],
    LICENSE          => 'perl_5',
    MIN_PERL_VERSION => '5.020',
    META_MERGE      => {
        resources   => {
            repository => {
                type => 'git',
                url  => 'git://github.com/castaway/prime-watched.git',
                web  => 'https://github.com/castaway/prime-watched',
            },
            license     => [ 'http://dev.perl.org/licenses/' ],
            bugtracker  => {
                web    => 'https://github.com/castaway/prime-watched/issues'
            }
        }
    }
);
