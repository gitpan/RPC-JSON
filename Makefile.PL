use ExtUtils::MakeMaker;

$xs = 0;

WriteMakefile(
    'NAME'          => 'RPC::JSON',
    'VERSION_FROM'  => 'lib/RPC/JSON.pm',
    PREREQ_PM       => {
                            'JSON',
                            'LWP::UserAgent',
                            'URI',
                            'JSON >= 2.00'
                       }
);

print "RPC::JSON needs tests, please consider contributing some!\n";
