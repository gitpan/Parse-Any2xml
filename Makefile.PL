use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'Parse::Any2xml',
    'VERSION_FROM'	=> 'Any2xml.pm', # finds $VERSION
    'PREREQ_PM'		=> { 'XML::Ximple' => 1.0 }, # e.g., Module::Name => 1.1
);
