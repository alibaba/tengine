package Test::Nginx::Socket::Lua;

use Test::Nginx::Socket -Base;

my $code = $ENV{TEST_NGINX_INIT_BY_LUA};

if ($code) {
    $code =~ s/\\/\\\\/g;
    $code =~ s/['"]/\\$&/g;

    Test::Nginx::Socket::set_http_config_filter(sub {
        my $config = shift;
        if ($config =~ /init_by_lua_file/) {
            return $config;
        }
        unless ($config =~ s{(?<!\#  )(?<!\# )(?<!\#)init_by_lua\s*(['"])((?:\\.|.)*)\1\s*;}{init_by_lua $1$code$2$1;}s) {
            $config .= "init_by_lua '$code';";
        }
        return $config;
    });
}

1;
__END__

=encoding utf-8

=head1 NAME

Test::Nginx::Socket::Lua - Socket-backed test scaffold for tests related to ngx_lua

=head1 SYNOPSIS

    use Test::Nginx::Socket::Lua;

    repeat_each(2);
    plan tests => repeat_each() * 3 * blocks();

    no_shuffle();
    run_tests();

    __DATA__

    === TEST 1: sanity
    --- config
        location = /t {
            content_by_lua '
                ngx.say("hello world")
            ';
        }
    --- request
        GET /t
    --- response_body
    hello world
    --- error_code: 200
    --- no_error_log
    [error]

=head1 Description

This module subclasses L<Test::Nginx::Socket> but adds support specific to tests related to the ngx_lua module.

Right now, it supports system environment variable C<TEST_NGINX_INIT_BY_LUA> by which the test runner can inject custom initialization Lua code for C<init_by_lua>. For example,

    export TEST_NGINX_INIT_BY_LUA="package.path = '$PWD/../lua-resty-core/lib/?.lua;' .. (package.path or '') require 'resty.core'"

=head1 AUTHOR

Yichun "agentzh" Zhang (章亦春) C<< <agentzh@gmail.com> >>, CloudFlare Inc.

=head1 COPYRIGHT & LICENSE

Copyright (c) 2009-2014, Yichun Zhang C<< <agentzh@gmail.com> >>, CloudFlare Inc.

This module is licensed under the terms of the BSD license.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

=over

=item *

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

=item *

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

=item *

Neither the name of the authors nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

=back

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=head1 SEE ALSO

L<Test::Nginx::Socket>, L<Test::Base>.

