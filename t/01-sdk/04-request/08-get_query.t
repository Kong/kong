use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use File::Spec;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__
