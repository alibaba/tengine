#!/usr/bin/perl

# Test for fastcgi backend.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

eval { require FCGI; };
plan(skip_all => 'FCGI not installed') if $@;
plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http fastcgi/)->plan(53);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        client_max_body_size 200M;

        location / {
            fastcgi_request_buffering off;
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_param REQUEST_URI $request_uri;
        }

        location /buffer {
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_param REQUEST_URI $request_uri;
        }
    }
}

EOF

$t->run_daemon(\&fastcgi_daemon);
$t->run();

###############################################################################

like(http_get('/'), qr/SEE-THIS/, 'fastcgi request');
like(http_get('/redir'), qr/302/, 'fastcgi redirect');
like(http_get('/'), qr/^3$/m, 'fastcgi third request');

unlike(http_head('/'), qr/SEE-THIS/, 'no data in HEAD');

like(http_get('/stderr'), qr/SEE-THIS/, 'large stderr handled');

sub http_post($;$;%) {
    my ($url, $body, %extra) = @_;
    my $len = length($body);

    return http(<<EOF, %extra);
POST $url HTTP/1.0
Host: localhost
Content-Length: $len
Content-Type: application/x-www-form-urlencoded

$body
EOF
}

my $k1 = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";

my $body;

$body= $k1;
like(http_post('/upload', $body), qr/1024/, 'post 1k file');

$body = $k1 x 10;
like(http_post('/upload', $body), qr/10240/, 'post 10k file');

$body = $k1 x 100;
like(http_post('/upload', $body), qr/102400/, 'post 100k file');

$body = $k1 x 1000;
like(http_post('/upload', $body), qr/1024000/, 'post 1M file');

$body = $k1;
like(http_post('/buffer', $body), qr/1024/, 'post 1k file buffered');

$body = $k1 x 10;
like(http_post('/buffer', $body), qr/10240/, 'post 10k file buffered');

$body = $k1 x 100;
like(http_post('/buffer', $body), qr/102400/, 'post 100k file buffered');

$body = $k1 x 1000;
like(http_post('/buffer', $body), qr/1024000/, 'post 1M file buffered');

###############################################################################

$t->stop();

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        client_max_body_size 200M;
        client_body_buffers 32 4k;

        location / {
            fastcgi_request_buffering off;
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_param REQUEST_URI $request_uri;
        }

        location /buffer {
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_param REQUEST_URI $request_uri;
        }
    }
}

EOF

$t->run();

$body= $k1;
like(http_post('/upload', $body), qr/1024/, 'post 1k file');

$body = $k1 x 10;
like(http_post('/upload', $body), qr/10240/, 'post 10k file');

$body = $k1 x 100;
like(http_post('/upload', $body), qr/102400/, 'post 100k file');

$body = $k1 x 1000;
like(http_post('/upload', $body), qr/1024000/, 'post 1M file');

$body = $k1;
like(http_post('/buffer', $body), qr/1024/, 'post 1k file buffered');

$body = $k1 x 10;
like(http_post('/buffer', $body), qr/10240/, 'post 10k file buffered');

$body = $k1 x 100;
like(http_post('/buffer', $body), qr/102400/, 'post 100k file buffered');

$body = $k1 x 1000;
like(http_post('/buffer', $body), qr/1024000/, 'post 1M file buffered');

###############################################################################

$t->stop();

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        client_max_body_size 200M;
        client_body_postpone_size 1;

        location / {
            fastcgi_request_buffering off;
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_param REQUEST_URI $request_uri;
        }

        location /buffer {
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_param REQUEST_URI $request_uri;
        }
    }
}

EOF

$t->run();

$body= $k1;
like(http_post('/upload', $body), qr/1024/, 'post 1k file');

$body = $k1 x 10;
like(http_post('/upload', $body), qr/10240/, 'post 10k file');

$body = $k1 x 100;
like(http_post('/upload', $body), qr/102400/, 'post 100k file');

$body = $k1 x 1000;
like(http_post('/upload', $body), qr/1024000/, 'post 1M file');

$body = $k1;
like(http_post('/buffer', $body), qr/1024/, 'post 1k file buffered');

$body = $k1 x 10;
like(http_post('/buffer', $body), qr/10240/, 'post 10k file buffered');

$body = $k1 x 100;
like(http_post('/buffer', $body), qr/102400/, 'post 100k file buffered');

$body = $k1 x 1000;
like(http_post('/buffer', $body), qr/1024000/, 'post 1M file buffered');

###############################################################################

$t->stop();

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        client_max_body_size 200M;
        client_body_postpone_size 4k;

        location / {
            fastcgi_request_buffering off;
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_param REQUEST_URI $request_uri;
        }

        location /buffer {
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_param REQUEST_URI $request_uri;
        }
    }
}

EOF

$t->run();

$body= $k1;
like(http_post('/upload', $body), qr/1024/, 'post 1k file');

$body = $k1 x 10;
like(http_post('/upload', $body), qr/10240/, 'post 10k file');

$body = $k1 x 100;
like(http_post('/upload', $body), qr/102400/, 'post 100k file');

$body = $k1 x 1000;
like(http_post('/upload', $body), qr/1024000/, 'post 1M file');

$body = $k1;
like(http_post('/buffer', $body), qr/1024/, 'post 1k file buffered');

$body = $k1 x 10;
like(http_post('/buffer', $body), qr/10240/, 'post 10k file buffered');

$body = $k1 x 100;
like(http_post('/buffer', $body), qr/102400/, 'post 100k file buffered');

$body = $k1 x 1000;
like(http_post('/buffer', $body), qr/1024000/, 'post 1M file buffered');

###############################################################################

$t->stop();

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        client_max_body_size 200M;
        client_body_postpone_size 16k;

        location / {
            fastcgi_request_buffering off;
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_param REQUEST_URI $request_uri;
        }

        location /buffer {
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_param REQUEST_URI $request_uri;
        }
    }
}

EOF

$t->run();

$body= $k1;
like(http_post('/upload', $body), qr/1024/, 'post 1k file');

$body = $k1 x 10;
like(http_post('/upload', $body), qr/10240/, 'post 10k file');

$body = $k1 x 100;
like(http_post('/upload', $body), qr/102400/, 'post 100k file');

$body = $k1 x 1000;
like(http_post('/upload', $body), qr/1024000/, 'post 1M file');

$body = $k1;
like(http_post('/buffer', $body), qr/1024/, 'post 1k file buffered');

$body = $k1 x 10;
like(http_post('/buffer', $body), qr/10240/, 'post 10k file buffered');

$body = $k1 x 100;
like(http_post('/buffer', $body), qr/102400/, 'post 100k file buffered');

$body = $k1 x 1000;
like(http_post('/buffer', $body), qr/1024000/, 'post 1M file buffered');


###############################################################################

$t->stop();

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        client_max_body_size 200M;
        client_body_postpone_size 2M;

        location / {
            fastcgi_request_buffering off;
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_param REQUEST_URI $request_uri;
        }

        location /buffer {
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_param REQUEST_URI $request_uri;
        }
    }
}

EOF

$t->run();

$body= $k1;
like(http_post('/upload', $body), qr/1024/, 'post 1k file');

$body = $k1 x 10;
like(http_post('/upload', $body), qr/10240/, 'post 10k file');

$body = $k1 x 100;
like(http_post('/upload', $body), qr/102400/, 'post 100k file');

$body = $k1 x 1000;
like(http_post('/upload', $body), qr/1024000/, 'post 1M file');

$body = $k1;
like(http_post('/buffer', $body), qr/1024/, 'post 1k file buffered');

$body = $k1 x 10;
like(http_post('/buffer', $body), qr/10240/, 'post 10k file buffered');

$body = $k1 x 100;
like(http_post('/buffer', $body), qr/102400/, 'post 100k file buffered');

$body = $k1 x 1000;
like(http_post('/buffer', $body), qr/1024000/, 'post 1M file buffered');


###############################################################################

sub fastcgi_daemon {
	my $socket = FCGI::OpenSocket('127.0.0.1:8081', 5);
	my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV,
		$socket);

	my $count;
	while( $request->Accept() >= 0 ) {
		$count++;

		if ($ENV{REQUEST_URI} eq '/stderr') {
			warn "sample stderr text" x 512;
		}

		if ($ENV{REQUEST_URI} eq '/upload' or $ENV{REQUEST_URI} eq '/buffer') {
            my $input = <STDIN>;
            my $len = length($input);
            #print $len;
		print <<EOF;
Content-Type: text/plain

$len
EOF
            next;
		}

		print <<EOF;
Location: http://127.0.0.1:8080/redirect
Content-Type: text/html

SEE-THIS
$count
EOF
	}

	FCGI::CloseSocket($socket);
}

###############################################################################
