#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for http proxy module related to use with the "if" directive.
# See http://wiki.nginx.org/IfIsEvil for more details.

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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite http_ssl/)
	->has_daemon('openssl')->plan(15);

$t->write_file_expand('nginx.conf', <<'EOF')->todo_alerts();

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://127.0.0.1:8081/;
        }

        # request was sent to backend without uri changed
        # to '/' due to if

        location /proxy-pass-uri {
            proxy_pass http://127.0.0.1:8081/replacement;

            if ($arg_if) {
                # nothing
            }

            location /proxy-pass-uri/inner {
                # no proxy_pass here, static

                if ($arg_if) {
                    # nothing
                }
            }
        }

        # same as the above, but there is a special handling
        # in configuration merge; it used to do wrong things with
        # nested locations though

        location /proxy-pass-uri-lmt {
            proxy_pass http://127.0.0.1:8081/replacement;

            limit_except POST {
                # nothing
            }

            location /proxy-pass-uri-lmt/inner {
                # no proxy_pass here, static

                limit_except POST {
                    # nothing
                }
            }
        }

        location /proxy-pass-uri-lmt-different {
            proxy_pass http://127.0.0.1:8081/replacement;

            limit_except POST {
                proxy_pass http://127.0.0.1:8081;
            }
        }

        # segmentation fault in old versions,
        # fixed to return 500 Internal Error in nginx 1.3.10

        location /proxy-inside-if-crash {

            set $true 1;

            if ($true) {
                # proxy_pass inside if
                proxy_pass http://127.0.0.1:8081;
            }

            if ($true) {
                # no handler here
            }
        }

        # normal proxy_pass and proxy_pass with variables
        # use distinct field, and inheritance should be mutually
        # exclusive

        location /variables {
            proxy_pass http://127.0.0.1:8081/outer/$host;

            if ($arg_if) {
                proxy_pass http://127.0.0.1:8081;
            }

            location /variables/inner {
                proxy_pass http://127.0.0.1:8081;
            }
        }

        # ssl context shouldn't be inherited into nested
        # locations with different proxy_pass, but should
        # be correctly inherited into if's

        location /ssl {
            proxy_pass https://127.0.0.1:8082/outer;

            if ($arg_if) {
                # inherited from outer
            }

            location /ssl/inner {
                proxy_pass http://127.0.0.1:8081;
            }
        }
    }

    server {
        listen       127.0.0.1:8081;
        listen       127.0.0.1:8082 ssl;
        server_name  localhost;

        ssl_certificate localhost.crt;
        ssl_certificate_key localhost.key;

        return 200 "uri:$uri\n";
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

$t->run();

###############################################################################

like(http_get('/'), qr!uri:/$!, 'proxy request');

like(http_get('/proxy-pass-uri'), qr!uri:/replacement$!,
	'proxy_pass uri changed');

# due to missing information about an original location where
# proxy_pass was specified, this used to pass request with
# original unmodified uri

like(http_get('/proxy-pass-uri?if=1'), qr!uri:/replacement$!,
	'proxy_pass uri changed in if');

like(http_get('/proxy-pass-uri/inner'), qr!404 Not Found!,
	'proxy_pass uri changed inner');
like(http_get('/proxy-pass-uri/inner?if=1'), qr!404 Not Found!,
	'proxy_pass uri changed inner in if');

# limit_except

like(http_get('/proxy-pass-uri-lmt'), qr!uri:/replacement$!,
	'proxy_pass uri and limit_except');

# special handling of limit_except resulted in wrong handling
# of requests in nested locations

like(http_get('/proxy-pass-uri-lmt/inner'), qr!404 Not Found!,
	'proxy_pass uri and limit_except, inner');

like(http_get('/proxy-pass-uri-lmt-different'),
	qr!uri:/proxy-pass-uri-lmt-different!,
	'proxy_pass and limit_except with different proxy_pass');

# segmentation fault in old versions,
# fixed to return 500 Internal Error in nginx 1.3.10

like(http_get('/proxy-inside-if-crash'), qr!500 Internal Server Error!,
	'proxy_pass inside if');

# normal proxy_pass and proxy_pass with variables
# use distinct field, and inheritance should be mutually
# exclusive, see ticket #645

like(http_get('/variables'), qr!uri:/outer!,
	'proxy_pass variables');
like(http_get('/variables?if=1'), qr!uri:/variables!,
	'proxy_pass variables if');
like(http_get('/variables/inner'), qr!uri:/variables/inner!,
	'proxy_pass variables nested');

# ssl context shouldn't be inherited into nested
# locations with different proxy_pass, but should
# be correctly inherited into if's

like(http_get('/ssl'), qr!uri:/outer!,
	'proxy_pass ssl');
like(http_get('/ssl?if=1'), qr!uri:/outer!,
	'proxy_pass ssl inside if');
like(http_get('/ssl/inner'), qr!uri:/ssl/inner!,
	'proxy_pass nossl inside ssl');

###############################################################################
