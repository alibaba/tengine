#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http backend returning response with trailers.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;
use Test::Nginx::HTTP3;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_v2 http_v3 cryptx proxy/)
	->has_daemon('openssl');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        listen       127.0.0.1:%%PORT_8980_UDP%% quic;
        server_name  localhost;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;

        http2 on;

        proxy_http_version 1.1;
        proxy_pass_trailers on;
        proxy_set_header Connection "te, close";
        proxy_set_header TE "trailers";

        location / {
            proxy_pass http://127.0.0.1:8081;
        }

        location /nobuffering {
            proxy_pass http://127.0.0.1:8081/;
            proxy_buffering off;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        add_header  Trailer "X-Trailer, X-Another";
        add_trailer X-Trailer foo;
        add_trailer X-Another bar;

        location / { }
    }
}

EOF

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

my $d = $t->testdir();

foreach my $name ('localhost') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->write_file('index.html', 'SEE-THIS');
$t->try_run('no proxy_pass_trailers')->plan(13);

###############################################################################

like(get('/'), qr/SEE-THIS.*X-Trailer: foo.*bar/si, 'trailers');
like(get('/nobuffering'), qr/SEE-THIS.*X-Trailer: foo.*bar/si,
	'trailers nobuffering');

# HTTP/2

my ($s, $sid, $frames, $frame);
$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET' },
	{ name => ':scheme', value => 'http' },
	{ name => ':path', value => '/', },
	{ name => ':authority', value => 'localhost' },
	{ name => 'te', value => 'trailers', mode => 2 }]});

$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
@$frames = grep { $_->{type} =~ "HEADERS|DATA" } @$frames;

$frame = shift @$frames;
is($frame->{headers}->{':status'}, 200, 'h2 header');
is($frame->{flags}, 4, 'h2 header flags');

$frame = shift @$frames;
is($frame->{data}, 'SEE-THIS', 'h2 data');
is($frame->{flags}, 0, 'h2 data flags');

$frame = shift @$frames;
is($frame->{headers}->{'x-trailer'}, 'foo', 'h2 trailer');
is($frame->{headers}->{'x-another'}, 'bar', 'h2 trailer 2');
is($frame->{flags}, 5, 'h2 trailer flags');

# HTTP/3

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET' },
	{ name => ':scheme', value => 'http' },
	{ name => ':path', value => '/', },
	{ name => ':authority', value => 'localhost' },
	{ name => 'te', value => 'trailers' }]});

$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
@$frames = grep { $_->{type} =~ "HEADERS|DATA" } @$frames;

$frame = shift @$frames;
is($frame->{headers}->{':status'}, 200, 'h3 header');

$frame = shift @$frames;
is($frame->{data}, 'SEE-THIS', 'h3 data');

$frame = shift @$frames;
is($frame->{headers}->{'x-trailer'}, 'foo', 'h3 trailer');
is($frame->{headers}->{'x-another'}, 'bar', 'h3 trailer 2');

###############################################################################

sub get {
	my ($uri) = @_;
	http(<<EOF);
GET $uri HTTP/1.1
Host: localhost
Connection: te, close
TE: trailers

EOF
}

###############################################################################
