use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }


use lib 'lib';
use File::Path;
use Test::Nginx;


my $NGINX = defined $ENV{TEST_NGINX_BINARY} ? $ENV{TEST_NGINX_BINARY}
        : '../nginx/objs/nginx';
my $t = Test::Nginx->new()->has(qw/http_ssl dyups with-debug/)->plan(105);

sub mhttp_get($;$;$;%) {
    my ($url, $host, $port, %extra) = @_;
    return mhttp(<<EOF, $port, %extra);
GET $url HTTP/1.0
Host: $host

EOF
}

sub mhttp_post($;$;$;%) {
    my ($url, $body, $port, %extra) = @_;
    my $len = length($body);
    return mhttp(<<EOF, $port, %extra);
POST $url HTTP/1.0
Host: localhost
Content-Length: $len

$body
EOF
}


sub mhttp_delete($;$;%) {
    my ($url, $port, %extra) = @_;
    return mhttp(<<EOF, $port, %extra);
DELETE $url HTTP/1.0
Host: localhost

EOF
}


sub mrun($;$) {
    my ($self, $conf) = @_;

    my $testdir = $self->{_testdir};

    if (defined $conf) {
        my $c = `cat $conf`;
        $self->write_file_expand('nginx.conf', $c);
    }

    my $pid = fork();
    die "Unable to fork(): $!\n" unless defined $pid;

    if ($pid == 0) {
        my @globals = $self->{_test_globals} ?
            () : ('-g', "pid $testdir/nginx.pid; "
                  . "error_log $testdir/error.log debug;");
        exec($NGINX, '-c', "$testdir/nginx.conf", '-p', "$testdir",
             @globals) or die "Unable to exec(): $!\n";
    }

    # wait for nginx to start

    $self->waitforfile("$testdir/nginx.pid")
        or die "Can't start nginx";

    $self->{_started} = 1;
    return $self;
}

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

warn "your test dir is ".$t->testdir();

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

worker_processes 1;

events {
    accept_mutex off;
}

http {
    %%TEST_GLOBALS_HTTP%%

    # Must be less than 2s (mhttp_get->mhttp->alarm(2)).
    # If upstream (e.g. "dyhost") is deleted by dyups api,
    # proxy module tries to resolve its name via public DNS server.
    resolver_timeout 500ms;

    upstream host1 {
        server 127.0.0.1:8088;
    }

    upstream host2 {
        server 127.0.0.1:8089;
    }

    server {
        listen   8080;

        location / {
            proxy_pass http://$host;
        }
    }

    server {
        listen 8088;
        location / {
            return 200 "8088";
        }
    }

    server {
        listen unix:/tmp/dyupssocket;
        location / {
            return 200 "unix";
        }
    }

    server {
        listen 8089;
        location / {
            return 200 "8089";
        }
    }

    server {
        listen 8081;
        location / {
            dyups_interface;
        }
    }
}
EOF

mrun($t);

###############################################################################
my $rep;
my $body;

$rep = qr/
host1
host2
/m;
like(mhttp_get('/list', 'localhost', 8081), $rep, '2013-02-26 16:51:46');
$rep = qr/
host1
server 127.0.0.1:8088 weight=1 .*

host2
server 127.0.0.1:8089 weight=1 .*
/m;
like(mhttp_get('/detail', 'localhost', 8081), $rep, '2013-02-26 17:30:07');
like(mhttp_get('/upstream/host1', 'localhost', 8081), qr/server 127.0.0.1:8088/m, '2013-02-26 17:35:19');

###############################################################################

like(mhttp_post('/upstream/dyhost', 'server 127.0.0.1:8088;', 8081), qr/success/m, '2013-02-26 16:51:51');
like(mhttp_get('/', 'dyhost', 8080), qr/8088/m, '2013-02-26 16:51:54');
like(mhttp_get('/', 'host1', 8080), qr/8088/m, '2013-02-26 17:36:42');
like(mhttp_get('/', 'host2', 8080), qr/8089/m, '2013-02-26 17:36:46');

$rep = qr/
host1
host2
dyhost
/m;
like(mhttp_get('/list', 'localhost', 8081), $rep, '2013-02-26 17:02:13');

$rep = qr/
host1
server 127.0.0.1:8088 weight=1 .*

host2
server 127.0.0.1:8089 weight=1 .*

dyhost
server 127.0.0.1:8088 weight=1 .*
/m;
like(mhttp_get('/detail', 'localhost', 8081), $rep, '2013-02-26 17:36:59');


like(mhttp_post('/upstream/dyhost', 'server 127.0.0.1:8088;server 127.0.0.1:8089;', 8081), qr/success/m, '2013-02-26 17:40:24');
like(mhttp_get('/', 'dyhost', 8080), qr/8088|8089/m, '2013-02-26 17:40:28');
like(mhttp_get('/', 'dyhost', 8080), qr/8089|8088/m, '2013-02-26 17:40:32');
like(mhttp_get('/', 'host1', 8080), qr/8088|8089/m, '2013-02-26 17:40:36');
like(mhttp_get('/', 'host2', 8080), qr/8089|8088/m, '2013-02-26 17:40:39');

$rep = qr/
host1
server 127.0.0.1:8088 weight=1 .*

host2
server 127.0.0.1:8089 weight=1 .*

dyhost
server 127.0.0.1:8088 weight=1 .*
server 127.0.0.1:8089 weight=1 .*
/m;
like(mhttp_get('/detail', 'localhost', 8081), $rep, '2013-02-26 17:41:09');


like(mhttp_delete('/upstream/dyhost', 8081), qr/success/m, '2013-02-26 16:51:57');
# use unlike() instead of like(502),
# proxy module tries to resolver "dyhost" via public DNS
# like(mhttp_get('/', 'dyhost', 8080), qr/502/m, '2013-02-26 16:52:00');
unlike(mhttp_get('/', 'dyhost', 8080), qr/8089|8088/m, '2013-02-26 17:40:32');
unlike(mhttp_get('/detail', 'localhost', 8081), qr/dyhost/, '2013-02-26 17:41:09');

$rep = qr/
host1
host2
/m;
like(mhttp_get('/list', 'localhost', 8081), $rep, '2013-02-26 17:00:54');

$rep = qr/
host1
server 127.0.0.1:8088 weight=1 .*

host2
server 127.0.0.1:8089 weight=1 .*
/m;
like(mhttp_get('/detail', 'localhost', 8081), $rep, '2013-02-26 17:42:27');

like(mhttp_delete('/upstream/dyhost', 8081), qr/404/m, '2013-02-26 17:44:34');

like(mhttp_delete('/upstream/host1', 8081), qr/success/m, '2013-02-26 17:08:00');
#like(mhttp_get('/', 'host1', 8080), qr/502/m, '2013-02-26 17:08:04');
unlike(mhttp_get('/', 'host1', 8080), qr/8088|8089/m, '2013-02-26 17:40:36');

$rep = qr/
host2
server 127.0.0.1:8089 weight=1 .*
/m;
like(mhttp_get('/detail', 'localhost', 8081), $rep, '2013-02-26 17:45:03');

like(mhttp_post('/upstream/dyhost', 'server 127.0.0.1:8088;', 8081), qr/success/m, '2013-02-26 17:05:20');
like(mhttp_get('/', 'dyhost', 8080), qr/8088/m, '2013-02-26 17:05:30');

$rep = qr/
host2
server 127.0.0.1:8089 weight=1 .*

dyhost
server 127.0.0.1:8088 weight=1 .*
/m;
like(mhttp_get('/detail', 'localhost', 8081), $rep, '2013-06-20 17:46:03');

like(mhttp_post('/upstream/dyhost', 'server 127.0.0.1:8088 weight=3; server 127.0.0.1:8089 weight=1;', 8081), qr/success/m, '2013-02-28 16:27:45');
like(mhttp_get('/', 'dyhost', 8080), qr/8088|8089/m, '2013-02-28 16:27:49');
like(mhttp_get('/', 'dyhost', 8080), qr/8088|8089/m, '2013-02-28 16:27:52');
like(mhttp_get('/', 'dyhost', 8080), qr/8088|8089/m, '2013-02-28 16:28:44');

like(mhttp_post('/upstream/dyhost', 'server 127.0.0.1:8088; server 127.0.0.1:18089 backup;', 8081), qr/success/m, '2013-02-28 16:23:41');
like(mhttp_get('/', 'dyhost', 8080), qr/8088/m, '2013-02-28 16:23:48');
like(mhttp_get('/', 'dyhost', 8080), qr/8088/m, '2013-02-28 16:25:32');
like(mhttp_get('/', 'dyhost', 8080), qr/8088/m, '2013-02-28 16:25:35');

like(mhttp_post('/upstream/dyhost', 'ip_hash;server 127.0.0.1:8088; server 127.0.0.1:8089;', 8081), qr/success/m, '2013-03-04 15:53:41');
like(mhttp_get('/', 'dyhost', 8080), qr/8088/m, '2013-03-04 15:53:44');
like(mhttp_get('/', 'dyhost', 8080), qr/8088/m, '2013-03-04 15:53:46');
like(mhttp_get('/', 'dyhost', 8080), qr/8088/m, '2013-03-04 15:53:49');

like(mhttp_post('/upstream/dyhost', 'ip_hash aaa;server 127.0.0.1:8088; server 127.0.0.1:8089;', 8081), qr/add server failed/m, '2013-03-05 15:36:40');
like(mhttp_post('/upstream/dyhost', 'ip_hash;aaserver 127.0.0.1:8088; server 127.0.0.1:8089;', 8081), qr/add server failed/m, '2013-03-05 15:37:25');

like(mhttp_post('/upstream/dyhost', 'server unix:/tmp/dyupssocket;', 8081), qr/success/m, '2013-03-05 16:13:11');
like(mhttp_get('/', 'dyhost', 8080), qr/unix/m, '2013-03-05 16:13:23');

like(mhttp_post('/upstream/dyhost', 'server 127.0.0.1:8088;check interval=3000 rise=2 fall=5 timeout=1000 type=http default_down=false;', 8081),
     qr/success/m, '2013-03-25 10:29:48');
like(mhttp_get('/', 'dyhost', 8080), qr/8088/m, '2013-03-25 10:39:02');
like(mhttp_delete('/upstream/dyhost', 8081), qr/success/m, '2013-03-25 10:39:28');

like(mhttp_post('/upstream/dyhost', 'server 127.0.0.1:8088;check interval=1000 rise=2 fall=5 timeout=1000 type=http default_down=true;', 8081),
     qr/success/m, '2013-03-25 10:49:44');
#like(mhttp_get('/', 'dyhost', 8080), qr/502/m, '2013-03-25 10:49:47');
unlike(mhttp_get('/', 'dyhost', 8080), qr/8088/m, '2013-03-25 10:39:02');
sleep(2);
like(mhttp_get('/', 'dyhost', 8080), qr/8088/m, '2013-03-25 10:50:41');
like(mhttp_delete('/upstream/dyhost', 8081), qr/success/m, '2013-03-25 10:49:51');


like(mhttp_post('/upstream/host1', 'server 127.0.0.1:8089;', 8081), qr/success/m, '2014-06-15 07:45:30');
like(mhttp_get('/', 'host1', 8080), qr/8089/m, '2014-06-15 07:45:33');

like(mhttp_post('/upstream/host1', 'server 127.0.0.1:8088;', 8081), qr/success/m, '2014-06-15 07:45:40');
like(mhttp_get('/', 'host1', 8080), qr/8088/m, '2014-06-15 07:45:43');



$t->stop();
unlink("/tmp/dyupssocket");

##############################################################################

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

worker_processes auto;

events {
    accept_mutex off;
}

http {
    %%TEST_GLOBALS_HTTP%%
    
    resolver_timeout 500ms;

    upstream host1 {
        server 127.0.0.1:8088;
    }

    upstream host2 {
        server 127.0.0.1:8089;
    }

    server {
        listen   8080;

        location / {
            proxy_pass http://$host;
        }
    }

    server {
        listen 8088;
        location / {
            return 200 "8088";
        }
    }

    server {
        listen unix:/tmp/dyupssocket;
        location / {
            return 200 "unix";
        }
    }

    server {
        listen 8089;
        location / {
            return 200 "8089";
        }
    }

    server {
        listen 8081;
        location / {
            dyups_interface;
        }
    }
}
EOF

mrun($t);


$rep = qr/
host1
host2
/m;
like(mhttp_get('/list', 'localhost', 8081), $rep, '2013-02-26 16:51:46');
$rep = qr/
host1
server 127.0.0.1:8088 weight=1 .*

host2
server 127.0.0.1:8089 weight=1 .*
/m;
like(mhttp_get('/detail', 'localhost', 8081), $rep, '2013-02-26 17:30:07');
like(mhttp_get('/upstream/host1', 'localhost', 8081), qr/server 127.0.0.1:8088/m, '2013-02-26 17:35:19');

###############################################################################

like(mhttp_post('/upstream/dyhost', 'server 127.0.0.1:8088;', 8081), qr/success/m, '2013-02-26 16:51:51');

$rep = qr/
host1
host2
dyhost
/m;
like(mhttp_get('/list', 'localhost', 8081), $rep, '2013-02-26 17:02:13');

$rep = qr/
host1
server 127.0.0.1:8088 weight=1 .*

host2
server 127.0.0.1:8089 weight=1 .*

dyhost
server 127.0.0.1:8088 weight=1 .*
/m;
like(mhttp_get('/detail', 'localhost', 8081), $rep, '2013-02-26 17:36:59');


like(mhttp_post('/upstream/dyhost', 'server 127.0.0.1:8088;server 127.0.0.1:8089;', 8081), qr/success/m, '2013-02-26 17:40:24');

$rep = qr/
host1
server 127.0.0.1:8088 weight=1 .*

host2
server 127.0.0.1:8089 weight=1 .*

dyhost
server 127.0.0.1:8088 weight=1 .*
server 127.0.0.1:8089 weight=1 .*
/m;
like(mhttp_get('/detail', 'localhost', 8081), $rep, '2013-02-26 17:41:09');


$rep = qr/
host1
host2
/m;
like(mhttp_get('/list', 'localhost', 8081), $rep, '2013-02-26 17:00:54');

$rep = qr/
host1
server 127.0.0.1:8088 weight=1 .*

host2
server 127.0.0.1:8089 weight=1 .*
/m;
like(mhttp_get('/detail', 'localhost', 8081), $rep, '2013-02-26 17:42:27');

$rep = qr/
host2
server 127.0.0.1:8089 weight=1 .*
/m;
like(mhttp_get('/detail', 'localhost', 8081), $rep, '2013-02-26 17:45:03');

like(mhttp_post('/upstream/dyhost', 'server 127.0.0.1:8088;', 8081), qr/success/m, '2013-02-26 17:05:20');

$rep = qr/
host2
server 127.0.0.1:8089 weight=1 .*

dyhost
server 127.0.0.1:8088 weight=1 .*
/m;
like(mhttp_get('/detail', 'localhost', 8081), $rep, '2013-02-26 17:46:03');

like(mhttp_post('/upstream/dyhost', 'server 127.0.0.1:8088 weight=3; server 127.0.0.1:8089 weight=1;', 8081), qr/success/m, '2013-02-28 16:27:45');

like(mhttp_post('/upstream/dyhost', 'server 127.0.0.1:8088; server 127.0.0.1:18089 backup;', 8081), qr/success/m, '2013-02-28 16:23:41');

like(mhttp_post('/upstream/dyhost', 'ip_hash;server 127.0.0.1:8088; server 127.0.0.1:8089;', 8081), qr/success/m, '2013-03-04 15:53:41');

like(mhttp_post('/upstream/dyhost', 'ip_hash aaa;server 127.0.0.1:8088; server 127.0.0.1:8089;', 8081), qr/add server failed/m, '2013-03-05 15:36:40');
like(mhttp_post('/upstream/dyhost', 'ip_hash;aaserver 127.0.0.1:8088; server 127.0.0.1:8089;', 8081), qr/add server failed/m, '2013-03-05 15:37:25');

like(mhttp_post('/upstream/dyhost', 'server unix:/tmp/dyupssocket;', 8081), qr/success/m, '2013-03-05 16:13:11');

$t->stop();
unlink("/tmp/dyupssocket");

##############################################################################

##############################################################################

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

worker_processes auto;

events {
    accept_mutex off;
}

http {
    %%TEST_GLOBALS_HTTP%%
    
    resolver_timeout 500ms;

    server {
        listen   8080;

        location / {
            proxy_pass http://$host;
        }
    }

    server {
        listen 8088;
        location / {
            return 200 "8088";
        }
    }

    server {
        listen unix:/tmp/dyupssocket;
        location / {
            return 200 "unix";
        }
    }

    server {
        listen 8089;
        location / {
            return 200 "8089";
        }
    }

    server {
        listen 8081;
        location / {
            dyups_interface;
        }

        location /lua/add {
            content_by_lua '
            local dyups = require "ngx.dyups"
            local status, rv = dyups.update("dyhost", [[server 127.0.0.1:8088;]]);
            ngx.print(status, rv)
            ';
        }

        location /lua/delete {
            content_by_lua '
            local dyups = require "ngx.dyups"
            local status, rv = dyups.delete("dyhost");
            ngx.print(status, rv)
            ';
        }
    }
}
EOF

mrun($t);


like(mhttp_get('/lua/add', 'localhost', 8081), qr/200success/m, '5/ 5 11:04:49 2014');
sleep(1);
like(mhttp_get('/', 'dyhost', 8080), qr/8088/m, '5/ 5 11:04:42 2014');
like(mhttp_get('/lua/delete', 'localhost', 8081), qr/200success/m, '5/ 5 11:08:08 2014');
sleep(1);
#like(mhttp_get('/', 'dyhost', 8080), qr/502/m, '5/ 5 11:08:16 2014');
unlike(mhttp_get('/', 'dyhost', 8080), qr/8088/m, '5/ 5 11:04:42 2014');


$t->stop();
unlink("/tmp/dyupssocket");

###############################################################################
# test ssl session reuse

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

worker_processes 1;

events {
    accept_mutex off;
}

error_log %%TESTDIR%%/error_ssl.log debug;

http {
    %%TEST_GLOBALS_HTTP%%
    
    resolver_timeout 500ms;

    server {
        listen 127.0.0.1:8080;

        location / {
            proxy_pass https://$host;
            proxy_set_header Connection close;
            proxy_ssl_session_reuse on;
            proxy_next_upstream http_500;
        }
    }

    server {
        listen 127.0.0.01:8087 ssl;
        listen 127.0.0.01:8088 ssl;

        error_log off;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;

        if ($arg_fail) {
            return 500;
        }

        return 200 "$server_port $ssl_session_reused";
    }

    server {
        listen 127.0.0.01:8089 ssl;
        listen 127.0.0.01:8090 ssl;

        error_log off;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;

        return 200 "$server_port $ssl_session_reused";
    }

    server {
        listen 8081;
        location / {
            dyups_interface;
        }
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
        . "-config '$d/openssl.conf' -subj '/CN=$name/' "
        . "-out '$d/$name.crt' -keyout '$d/$name.key' "
        . ">>$d/openssl.out 2>&1") == 0
        or die "Can't create certificate for $name: $!\n";
}

mrun($t);

my $count;
my $errlog;

# test single server
print("+ ssl session reuse: upstream: single server\n");
like(mhttp_post('/upstream/dyhost', 'server 127.0.0.1:8088;', 8081), qr/success/m, 'add single server');
sleep(1);
like(mhttp_get('/', 'dyhost', 8080), qr/8088 \./m, 'ssl session not reused and saved');
like(mhttp_get('/', 'dyhost', 8080), qr/8088 r/m, 'ssl session reused');
like(mhttp_get('/', 'dyhost', 8080), qr/8088 r/m, 'ssl session reused');
like(mhttp_delete('/upstream/dyhost', 8081), qr/success/m, 'delete upstream of single server');
sleep(1);

$errlog = $t->read_file("error_ssl.log");
$count = () = $errlog =~ /\[dyups\] free old session:/g;
is($count, 1, "debug log: free ssl session");

unlike(mhttp_get('/', 'dyhost', 8080), qr/8088/m, 'single server has been deleted');
like(mhttp_post('/upstream/dyhost', 'server 127.0.0.1:8088;', 8081), qr/success/m, 'add single server again');
sleep(1);
like(mhttp_get('/', 'dyhost', 8080), qr/8088 \./m, 'ssl session not reused (ssl session has been freed)');
like(mhttp_get('/', 'dyhost', 8080), qr/8088 r/m, 'ssl session reused');

# test single server and single backup server

print("+ ssl session reuse: upstream: single server and single backup server\n");
like(mhttp_post('/upstream/dyhost', 'server 127.0.0.1:8088 fail_timeout=60s max_fails=1; server 127.0.0.1:8089 backup;', 8081), qr/success/m, 'update upstream dyhost with single server and single backup');
sleep(1);

$errlog = $t->read_file("error_ssl.log");
$count = () = $errlog =~ /\[dyups\] free old session:/g;
is($count, 2, "debug log: free ssl session after updating upstream dyhost");

like(mhttp_get('/', 'dyhost', 8080), qr/8088 \./m, 'ssl session not reused, save ssl session');
like(mhttp_get('/?fail=yes', 'dyhost', 8080), qr/8089 \./m, 'try backup: ssl session not reused and saved');
like(mhttp_get('/', 'dyhost', 8080), qr/8089 r/m, 'backup server: ssl session reused');
like(mhttp_delete('/upstream/dyhost', 8081), qr/success/m, 'delete upstream of single server and single backup server');
sleep(1);

$errlog = $t->read_file("error_ssl.log");
$count = () = $errlog =~ /\[dyups\] free old session:/g;
is($count, 4, "debug log: free ssl session");

# test multiple servers and multiple backup servers
print("+ ssl session reuse: upstream: multiple servers and multiple backup servers\n");
like(mhttp_post('/upstream/dyhost2',
        'server 127.0.0.1:8087 fail_timeout=60s max_fails=1;
         server 127.0.0.1:8088 fail_timeout=60s max_fails=1;
         server 127.0.0.1:8089 backup;
         server 127.0.0.1:8090 backup;',
         8081),
     qr/success/m,
     'add upstream of multiple servers and backups');
my $r;
$r = mhttp_get('/', 'dyhost2', 8080) .
     mhttp_get('/', 'dyhost2', 8080);
like($r, qr/8087 \./m, 'ssl session not reused, save ssl session');
like($r, qr/8088 \./m, 'ssl session not reused, save ssl session');
$r = mhttp_get('/', 'dyhost2', 8080) .
     mhttp_get('/', 'dyhost2', 8080);
like($r, qr/8087 r/m, '8087: ssl session reused');
like($r, qr/8088 r/m, '8088: ssl session reused');

$r = mhttp_get('/?fail=yes', 'dyhost2', 8080) .
     mhttp_get('/', 'dyhost2', 8080);
like($r, qr/8089 \./m, 'try backup: ssl session not reused, save ssl session');
like($r, qr/8090 \./m, 'try backup: ssl session not reused, save ssl session');
$r = mhttp_get('/', 'dyhost2', 8080);
$r = $r . mhttp_get('/', 'dyhost2', 8080);
like($r, qr/8089 r/m, 'backup 8089: ssl session reused');
like($r, qr/8090 r/m, 'backup 8090: ssl session reused');
like(mhttp_delete('/upstream/dyhost2', 8081), qr/success/m, 'delete upstream of multiple servers and backups');
sleep(1);
$errlog = $t->read_file("error_ssl.log");
$count = () = $errlog =~ /\[dyups\] free old session:/g;
is($count, 8, "debug log: free ssl session");

$t->stop();

###############################################################################

sub mhttp($;$;%) {
    my ($request, $port, %extra) = @_;
    my $reply;
    eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        local $SIG{PIPE} = sub { die "sigpipe\n" };
        alarm(2);
        my $s = IO::Socket::INET->new(
            Proto => "tcp",
            PeerAddr => "127.0.0.1:$port"
            );
        log_out($request);
        $s->print($request);
        local $/;
        select undef, undef, undef, $extra{sleep} if $extra{sleep};
        return '' if $extra{aborted};
        $reply = $s->getline();
        alarm(0);
    };
    alarm(0);
    if ($@) {
        log_in("died: $@");
        return undef;
    }
    log_in($reply);
    return $reply;
}
