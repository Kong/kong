use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 2);

run_tests();

__DATA__
