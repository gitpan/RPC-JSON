#!perl -wT

use warnings;
use strict;

use Test::More tests => 4;

use_ok("RPC::JSON");
my $jsonrpc1 = RPC::JSON->new(
    "http://www.simplymapped.com/services/geocode/json.smd" );
ok($jsonrpc1, "Creating RPC::JSON object with SMD URI");

my $jsonrpc2 = RPC::JSON->new(
    smd => "http://www.simplymapped.com/services/geocode/json.smd" );
ok($jsonrpc2, "Creating RPC::JSON object with hash");

my $jsonrpc3 = RPC::JSON->new({
    smd => "http://www.simplymapped.com/services/geocode/json.smd" });
ok($jsonrpc3, "Creating RPC::JSON object with hash reference");

$jsonrpc3->geocode("1234 Se 10th St Vancouver, WA");
