#!/usr/bin/perl

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

my $t = Test::Nginx->new()->has(qw/http fastcgi/)->plan(30)
        ->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
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

$t->stop();
$t->stop_daemons();

###############################################################################

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

worker_processes auto;

events {
    accept_mutex off;
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream fastcgi {
        server 127.0.0.1:8081;
        check interval=3000 rise=2 fall=3 timeout=1000 type=fastcgi default_down=false;
        check_fastcgi_param "REQUEST_METHOD" "GET";
        check_fastcgi_param "REQUEST_URI" "/redir";
        check_http_expect_alive http_3xx;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            fastcgi_pass fastcgi;
            fastcgi_param REQUEST_URI $request_uri;
        }
    }
}

EOF

$t->run();
$t->run_daemon(\&fastcgi_daemon);

###############################################################################

like(http_get('/'), qr/SEE-THIS/, 'fastcgi request default_down=false');
like(http_get('/redir'), qr/302/, 'fastcgi redirect default_down=false');
like(http_get('/'), qr/^3$/m, 'fastcgi third request default_down=false');

unlike(http_head('/'), qr/SEE-THIS/, 'no data in HEAD default_down=false');

like(http_get('/stderr'), qr/SEE-THIS/, 'large stderr handled default_down=false');

$t->stop();
$t->stop_daemons();

###############################################################################

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

worker_processes auto;

events {
    accept_mutex off;
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream fastcgi {
        server 127.0.0.1:8081;
        check interval=3000 rise=2 fall=3 timeout=1000 type=fastcgi;
        check_fastcgi_param "REQUEST_METHOD" "GET";
        check_fastcgi_param "REQUEST_URI" "/redir";
        check_http_expect_alive http_3xx;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            fastcgi_pass fastcgi;
            fastcgi_param REQUEST_URI $request_uri;
        }
    }
}

EOF

$t->run();
$t->run_daemon(\&fastcgi_daemon);

###############################################################################

like(http_get('/'), qr/502/m, 'fastcgi request default_down=true');
like(http_get('/redir'), qr/502/m, 'fastcgi redirect default_down=true');
like(http_get('/'), qr/502/m, 'fastcgi third request default_down=true');
like(http_head('/'), qr/502/m, 'no data in HEAD default_down=true');
like(http_get('/stderr'), qr/502/m, 'large stderr handled default_down=true');

$t->stop();
$t->stop_daemons();

###############################################################################

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

worker_processes auto;

events {
    accept_mutex off;
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream fastcgi {
        server 127.0.0.1:8081;
        check interval=3000 rise=2 fall=3 timeout=1000 type=fastcgi;
        check_fastcgi_param "REQUEST_METHOD" "GET";
        check_fastcgi_param "REQUEST_URI" "/redir";
        check_http_expect_alive http_3xx;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            fastcgi_pass fastcgi;
            fastcgi_param REQUEST_URI $request_uri;
        }
    }
}

EOF

$t->run();
$t->run_daemon(\&fastcgi_daemon);

###############################################################################

sleep(5);

like(http_get('/'), qr/SEE-THIS/, 'fastcgi request default_down=false check 302');
like(http_get('/redir'), qr/302/, 'fastcgi redirect default_down=false check 302');
like(http_get('/'), qr/^\d$/m, 'fastcgi third request default_down=false check 302');

unlike(http_head('/'), qr/SEE-THIS/, 'no data in HEAD default_down=false check 302');

like(http_get('/stderr'), qr/SEE-THIS/, 'large stderr handled default_down=false check 302');

$t->stop();
$t->stop_daemons();


###############################################################################

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

worker_processes auto;

events {
    accept_mutex off;
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream fastcgi {
        server 127.0.0.1:8081;
        check interval=1000 rise=1 fall=1 timeout=1000 type=fastcgi;
        check_fastcgi_param "REQUEST_METHOD" "GET";
        check_fastcgi_param "REQUEST_URI" "/404";
        check_http_expect_alive http_2xx;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            fastcgi_pass fastcgi;
            fastcgi_param REQUEST_URI $request_uri;
        }
    }
}

EOF

$t->run();
$t->run_daemon(\&fastcgi_daemon);

###############################################################################

sleep(5);

like(http_get('/'), qr/502/m, 'fastcgi request default_down=true check status heaer');
like(http_get('/redir'), qr/502/m, 'fastcgi redirect default_down=true check status heaer');
like(http_get('/'), qr/502/m, 'fastcgi third request default_down=true check status heaer');
like(http_head('/'), qr/502/m, 'no data in HEAD default_down=true check status heaer');
like(http_get('/stderr'), qr/502/m, 'large stderr handled default_down=true check status heaer');

$t->stop();
$t->stop_daemons();


###############################################################################

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

worker_processes auto;

events {
    accept_mutex off;
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream fastcgi {
        server 127.0.0.1:8081;
        check interval=1000 rise=1 fall=1 timeout=1000 type=fastcgi;
        check_fastcgi_param "REQUEST_METHOD" "GET";
        check_fastcgi_param "REQUEST_URI" "/";
        check_http_expect_alive http_4xx;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            fastcgi_pass fastcgi;
            fastcgi_param REQUEST_URI $request_uri;
        }
    }
}

EOF

$t->run();
$t->run_daemon(\&fastcgi_daemon);

###############################################################################

sleep(5);

like(http_get('/'), qr/SEE-THIS/, 'fastcgi request default_down=false without status header');
like(http_get('/redir'), qr/302/, 'fastcgi redirect default_down=false without status header');
like(http_get('/'), qr/^\d$/m, 'fastcgi third request default_down=false without status header');

unlike(http_head('/'), qr/SEE-THIS/, 'no data in HEAD default_down=false without status header');

like(http_get('/stderr'), qr/SEE-THIS/, 'large stderr handled default_down=false without status header');

$t->stop();
$t->stop_daemons();


###############################################################################

sub fastcgi_daemon {
    my $socket = FCGI::OpenSocket('127.0.0.1:8081', 5);
    my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV,
                                $socket);

    my $count;
    while ( $request->Accept() >= 0 ) {
        $count++;

        if ($ENV{REQUEST_URI} eq '/stderr') {
            warn "sample stderr text" x 512;
        }

        if ($ENV{REQUEST_URI} eq '/404') {
            print <<EOF;
Status: 404
EOF
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
