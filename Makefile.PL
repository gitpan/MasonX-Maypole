use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'MasonX::Maypole',
    'VERSION_FROM'	=> 'Maypole.pm', # finds $VERSION
    'PREREQ_PM'		=> { HTML::Mason => 1,
                         Maypole     => 1,
                         }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'Maypole.pm', # retrieve abstract from module
       AUTHOR     => 'David R. Baird <cpan@riverside-cms.co.uk>') : ()),
);
 