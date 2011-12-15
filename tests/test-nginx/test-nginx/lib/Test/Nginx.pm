package Test::Nginx;

use strict;
use warnings;

our $VERSION = '0.17';

__END__

=encoding utf-8

=head1 NAME

Test::Nginx - Testing modules for Nginx C module development

=head1 DESCRIPTION

This distribution provides two testing modules for Nginx C module development:

=over

=item *

L<Test::Nginx::LWP>

=item *

L<Test::Nginx::Socket>

=back

All of them are based on L<Test::Base>.

Usually, L<Test::Nginx::Socket> is preferred because it works on a much lower
level and not that fault tolerant like L<Test::Nginx::LWP>.

Also, a lot of connection hang issues (like wrong C<< r->main->count >> value in nginx
0.8.x) can only be captured by L<Test::Nginx::Socket> because Perl's L<LWP::UserAgent> client
will close the connection itself which will conceal such issues from
the testers.

Test::Nginx automatically starts an nginx instance (from the C<PATH> env)
rooted at t/servroot/ and the default config template makes this nginx
instance listen on the port C<1984> by default. One can specify a different
port number by setting his port number to the C<TEST_NGINX_PORT> environment,
as in

    export TEST_NGINX_PORT=1989

=head2 etcproxy integration

The default settings in etcproxy (https://github.com/chaoslawful/etcproxy)
makes this small TCP proxy split the TCP packets into bytes and introduce 1 ms latency among them.

There's usually various TCP chains that we can put etcproxy into, for example

=head3 Test::Nginx <=> nginx

  $ ./etcproxy 1234 1984

Here we tell etcproxy to listen on port 1234 and to delegate all the
TCP traffic to the port 1984, the default port that Test::Nginx makes
nginx listen to.

And then we tell Test::Nginx to test against the port 1234, where
etcproxy listens on, rather than the port 1984 that nginx directly
listens on:

  $ TEST_NGINX_CLIENT_PORT=1234 prove -r t/

Then the TCP chain now looks like this:

  Test::Nginx <=> etcproxy (1234) <=> nginx (1984)

So etcproxy can effectively emulate extreme network conditions and
exercise "unusual" code paths in your nginx server by your tests.

In practice, *tons* of weird bugs can be captured by this setting.
Even ourselves didn't expect that this simple approach is so
effective.

=head3 nginx <=> memcached

We first start the memcached server daemon on port 11211:

   memcached -p 11211 -vv

and then we another etcproxy instance to listen on port 11984 like this

   $ ./etcproxy 11984 11211

Then we tell our t/foo.t test script to connect to 11984 rather than 11211:

  # foo.t
  use Test::Nginx::Socket;
  repeat_each(1);
  plan tests => 2 * repeat_each() * blocks();
  $ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;  # make this env take a default value
  run_tests();

  __DATA__

  === TEST 1: sanity
  --- config
  location /foo {
       set $memc_cmd set;
       set $memc_key foo;
       set $memc_value bar;
       memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
  }
  --- request
      GET /foo
  --- response_body_like: STORED

The Test::Nginx library will automatically expand the special macro
C<$TEST_NGINX_MEMCACHED_PORT> to the environment with the same name.
You can define your own C<$TEST_NGINX_BLAH_BLAH_PORT> macros as long as
its prefix is C<TEST_NGINX_> and all in upper case letters.

And now we can run your test script against the etcproxy port 11984:

   TEST_NGINX_MEMCACHED_PORT=11984 prove t/foo.t

Then the TCP chains look like this:

   Test::Nginx <=> nginx (1984) <=> etcproxy (11984) <=> memcached (11211)

If C<TEST_NGINX_MEMCACHED_PORT> is not set, then it will take the default
value 11211, which is what we want when there's no etcproxy
configured:

   Test::Nginx <=> nginx (1984) <=> memcached (11211)

This approach also works for proxied mysql and postgres traffic.
Please see the live test suite of ngx_drizzle and ngx_postgres for
more details.

Usually we set both C<TEST_NGINX_CLIENT_PORT> and
C<TEST_NGINX_MEMCACHED_PORT> (and etc) at the same time, effectively
yielding the following chain:

   Test::Nginx <=> etcproxy (1234) <=> nginx (1984) <=> etcproxy (11984) <=> memcached (11211)

as long as you run two separate etcproxy instances in two separate terminals.

It's easy to verify if the traffic actually goes through your etcproxy
server. Just check if the terminal running etcproxy emits outputs. By
default, etcproxy always dump out the incoming and outgoing data to
stdout/stderr.

=head2 valgrind integration

Test::Nginx has integrated support for valgrind (L<http://valgrind.org>) even though by
default it does not bother running it with the tests because valgrind
will significantly slow down the test sutie.

First ensure that your valgrind executable visible in your PATH env.
And then run your test suite with the C<TEST_NGINX_USE_VALGRIND> env set
to true:

   TEST_NGINX_USE_VALGRIND=1 prove -r t

If you see false alarms, you do have a chance to skip them by defining
a ./valgrind.suppress file at the root of your module source tree, as
in

L<https://github.com/chaoslawful/drizzle-nginx-module/blob/master/valgrind.suppress>

This is the suppression file for ngx_drizzle. Test::Nginx will
automatically use it to start nginx with valgrind memcheck if this
file does exist at the expected location.

If you do see a lot of "Connection refused" errors while running the
tests this way, then you probably have a slow machine (or a very busy
one) that the default waiting time is not sufficient for valgrind to
start. You can define the sleep time to a larger value by setting the
C<TEST_NGINX_SLEEP> env:

   TEST_NGINX_SLEEP=1 prove -r t

The time unit used here is "second". The default sleep setting just
fits my ThinkPad (C<Core2Duo T9600>).

Applying the no-pool patch to your nginx core is recommended while
running nginx with valgrind:

L<https://github.com/shrimp/no-pool-nginx>

The nginx memory pool can prevent valgrind from spotting lots of
invalid memory reads/writes as well as certain double-free errors. We
did find a lot more memory issues in many of our modules when we first
introduced the no-pool patch in practice ;)

There's also more advanced features in Test::Nginx that have never
documented. I'd like to write more about them in the near future ;)


=head1 Nginx C modules that use Test::Nginx to drive their test suites

=over

=item ngx_echo

L<http://github.com/agentzh/echo-nginx-module>

=item ngx_headers_more

L<http://github.com/agentzh/headers-more-nginx-module>

=item ngx_chunkin

L<http://wiki.nginx.org/NginxHttpChunkinModule>

=item ngx_memc

L<http://wiki.nginx.org/NginxHttpMemcModule>

=item ngx_drizzle

L<http://github.com/chaoslawful/drizzle-nginx-module>

=item ngx_rds_json

L<http://github.com/agentzh/rds-json-nginx-module>

=item ngx_xss

L<http://github.com/agentzh/xss-nginx-module>

=item ngx_srcache

L<http://github.com/agentzh/srcache-nginx-module>

=item ngx_lua

L<http://github.com/chaoslawful/lua-nginx-module>

=item ngx_set_misc

L<http://github.com/agentzh/set-misc-nginx-module>

=item ngx_array_var

L<http://github.com/agentzh/array-var-nginx-module>

=item ngx_form_input

L<http://github.com/calio/form-input-nginx-module>

=item ngx_iconv

L<http://github.com/calio/iconv-nginx-module>

=item ngx_set_cconv

L<http://github.com/liseen/set-cconv-nginx-module>

=item ngx_postgres

L<http://github.com/FRiCKLE/ngx_postgres>

=item ngx_coolkit

L<http://github.com/FRiCKLE/ngx_coolkit>

=back

=head1 SOURCE REPOSITORY

This module has a Git repository on Github, which has access for all.

    http://github.com/agentzh/test-nginx

If you want a commit bit, feel free to drop me a line.

=head1 AUTHORS

agentzh (章亦春) C<< <agentzh@gmail.com> >>

Antoine BONAVITA C<< <antoine.bonavita@gmail.com> >>

=head1 COPYRIGHT & LICENSE

Copyright (c) 2009-2011, Taobao Inc., Alibaba Group (L<http://www.taobao.com>).

Copyright (c) 2009-2011, agentzh C<< <agentzh@gmail.com> >>.

Copyright (c) 2011, Antoine Bonavita C<< <antoine.bonavita@gmail.com> >>.

This module is licensed under the terms of the BSD license.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

=over

=item *

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

=item *

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

=item *

Neither the name of the Taobao Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission. 

=back

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 

=head1 SEE ALSO

L<Test::Nginx::LWP>, L<Test::Nginx::Socket>, L<Test::Base>.

