package Test::Nginx;

# (C) Maxim Dounin

# Generic module for nginx tests.

###############################################################################

use warnings;
use strict;

use base qw/ Exporter /;

our @EXPORT = qw/ log_in log_out http http_get http_head port /;
our @EXPORT_OK = qw/ http_gzip_request http_gzip_like http_start http_end /;
our %EXPORT_TAGS = (
	gzip => [ qw/ http_gzip_request http_gzip_like / ]
);

###############################################################################

use File::Path qw/ rmtree /;
use File::Spec qw//;
use File::Temp qw/ tempdir /;
use IO::Socket;
use POSIX qw/ waitpid WNOHANG /;
use Socket qw/ CRLF /;
use Test::More qw//;

###############################################################################

our $NGINX = defined $ENV{TEST_NGINX_BINARY} ? $ENV{TEST_NGINX_BINARY}
	: '../nginx/objs/nginx';
our %ports = ();

sub new {
	my $self = {};
	bless $self;

	$self->{_pid} = $$;
	$self->{_alerts} = 1;

	$self->{_testdir} = tempdir(
		'nginx-test-XXXXXXXXXX',
		TMPDIR => 1
	)
		or die "Can't create temp directory: $!\n";
	$self->{_testdir} =~ s!\\!/!g if $^O eq 'MSWin32';
	mkdir "$self->{_testdir}/logs"
		or die "Can't create logs directory: $!\n";

	Test::More::BAIL_OUT("no $NGINX binary found")
		unless -x $NGINX;

	return $self;
}

sub DESTROY {
	my ($self) = @_;
	local $?;

	return if $self->{_pid} != $$;

	$self->stop();
	$self->stop_daemons();

	if (Test::More->builder->expected_tests) {
		local $Test::Nginx::TODO = 'alerts' unless $self->{_alerts};

		my @alerts = $self->read_file('error.log') =~ /.+\[alert\].+/gm;

		if ($^O eq 'solaris') {
			$Test::Nginx::TODO = 'alerts' if @alerts
				&& ! grep { $_ !~ /phantom event/ } @alerts;
		}
		if ($^O eq 'MSWin32') {
			my $re = qr/CloseHandle|TerminateProcess/;
			$Test::Nginx::TODO = 'alerts' if @alerts
				&& ! grep { $_ !~ $re } @alerts;
		}

		Test::More::is(join("\n", @alerts), '', 'no alerts');
	}

	if (Test::More->builder->expected_tests) {
		local $Test::Nginx::TODO;
		my $errors = $self->read_file('error.log');
		$errors = join "\n", $errors =~ /.+Sanitizer.+/gm;
		Test::More::is($errors, '', 'no sanitizer errors');
	}

	if ($ENV{TEST_NGINX_CATLOG}) {
		system("cat $self->{_testdir}/error.log");
	}
	if (not $ENV{TEST_NGINX_LEAVE}) {
		eval { rmtree($self->{_testdir}); };
	}
}

sub has($;) {
	my ($self, @features) = @_;

	foreach my $feature (@features) {
		Test::More::plan(skip_all => "no $feature available")
			unless $self->has_module($feature)
			or $self->has_feature($feature);
	}

	return $self;
}

sub has_module($) {
	my ($self, $feature) = @_;

	my %regex = (
		sni	=> 'TLS SNI support enabled',
		mail	=> '--with-mail((?!\S)|=dynamic)',
		flv	=> '--with-http_flv_module',
		perl	=> '--with-http_perl_module',
		auth_request
			=> '--with-http_auth_request_module',
		realip	=> '--with-http_realip_module',
		sub	=> '--with-http_sub_module',
		charset	=> '(?s)^(?!.*--without-http_charset_module)',
		gzip	=> '(?s)^(?!.*--without-http_gzip_module)',
		ssi	=> '(?s)^(?!.*--without-http_ssi_module)',
		mirror	=> '(?s)^(?!.*--without-http_mirror_module)',
		userid	=> '(?s)^(?!.*--without-http_userid_module)',
		access	=> '(?s)^(?!.*--without-http_access_module)',
		auth_basic
			=> '(?s)^(?!.*--without-http_auth_basic_module)',
		autoindex
			=> '(?s)^(?!.*--without-http_autoindex_module)',
		geo	=> '(?s)^(?!.*--without-http_geo_module)',
		map	=> '(?s)^(?!.*--without-http_map_module)',
		referer	=> '(?s)^(?!.*--without-http_referer_module)',
		rewrite	=> '(?s)^(?!.*--without-http_rewrite_module)',
		proxy	=> '(?s)^(?!.*--without-http_proxy_module)',
		fastcgi	=> '(?s)^(?!.*--without-http_fastcgi_module)',
		uwsgi	=> '(?s)^(?!.*--without-http_uwsgi_module)',
		scgi	=> '(?s)^(?!.*--without-http_scgi_module)',
		grpc	=> '(?s)^(?!.*--without-http_grpc_module)',
		memcached
			=> '(?s)^(?!.*--without-http_memcached_module)',
		limit_conn
			=> '(?s)^(?!.*--without-http_limit_conn_module)',
		limit_req
			=> '(?s)^(?!.*--without-http_limit_req_module)',
		empty_gif
			=> '(?s)^(?!.*--without-http_empty_gif_module)',
		browser	=> '(?s)^(?!.*--without-http_browser_module)',
		upstream_hash
			=> '(?s)^(?!.*--without-http_upstream_hash_module)',
		upstream_ip_hash
			=> '(?s)^(?!.*--without-http_upstream_ip_hash_module)',
		upstream_least_conn
			=> '(?s)^(?!.*--without-http_upstream_least_conn_mod)',
		upstream_random
			=> '(?s)^(?!.*--without-http_upstream_random_module)',
		upstream_keepalive
			=> '(?s)^(?!.*--without-http_upstream_keepalive_modu)',
		upstream_zone
			=> '(?s)^(?!.*--without-http_upstream_zone_module)',
		http	=> '(?s)^(?!.*--without-http(?!\S))',
		cache	=> '(?s)^(?!.*--without-http-cache)',
		pop3	=> '(?s)^(?!.*--without-mail_pop3_module)',
		imap	=> '(?s)^(?!.*--without-mail_imap_module)',
		smtp	=> '(?s)^(?!.*--without-mail_smtp_module)',
		pcre	=> '(?s)^(?!.*--without-pcre)',
		split_clients
			=> '(?s)^(?!.*--without-http_split_clients_module)',
		stream	=> '--with-stream((?!\S)|=dynamic)',
		stream_access
			=> '(?s)^(?!.*--without-stream_access_module)',
		stream_geo
			=> '(?s)^(?!.*--without-stream_geo_module)',
		stream_limit_conn
			=> '(?s)^(?!.*--without-stream_limit_conn_module)',
		stream_map
			=> '(?s)^(?!.*--without-stream_map_module)',
		stream_return
			=> '(?s)^(?!.*--without-stream_return_module)',
		stream_split_clients
			=> '(?s)^(?!.*--without-stream_split_clients_module)',
		stream_ssl
			=> '--with-stream_ssl_module',
		stream_sni
			=> '--with-stream_sni',
		stream_upstream_hash
			=> '(?s)^(?!.*--without-stream_upstream_hash_module)',
		stream_upstream_least_conn
			=> '(?s)^(?!.*--without-stream_upstream_least_conn_m)',
		stream_upstream_random
			=> '(?s)^(?!.*--without-stream_upstream_random_modul)',
		stream_upstream_zone
			=> '(?s)^(?!.*--without-stream_upstream_zone_module)',
	);

	my $re = $regex{$feature};
	$re = $feature if !defined $re;

	$self->{_configure_args} = `$NGINX -V 2>&1`
		if !defined $self->{_configure_args};

	return 1 if $self->{_configure_args} =~ $re;

	my %modules = (
		http_geoip
			=> 'ngx_http_geoip_module',
		image_filter
			=> 'ngx_http_image_filter_module',
		perl	=> 'ngx_http_perl_module',
		xslt	=> 'ngx_http_xslt_filter_module',
		mail	=> 'ngx_mail_module',
		stream	=> 'ngx_stream_module',
		stream_geoip
			=> 'ngx_stream_geoip_module',
	);

	my $module = $modules{$feature};
	if (defined $module && defined $ENV{TEST_NGINX_GLOBALS}) {
		$re = qr/load_module\s+[^;]*\Q$module\E[-\w]*\.so\s*;/;
		return 1 if $ENV{TEST_NGINX_GLOBALS} =~ $re;
	}

	return 0;
}

sub has_feature($) {
	my ($self, $feature) = @_;

	if ($feature eq 'symlink') {
		return $^O ne 'MSWin32';
	}

	if ($feature eq 'unix') {
		return $^O ne 'MSWin32';
	}

	if ($feature eq 'udp') {
		return $^O ne 'MSWin32';
	}

	return 0;
}

sub has_version($) {
	my ($self, $need) = @_;

	$self->{_configure_args} = `$NGINX -V 2>&1`
		if !defined $self->{_configure_args};

	$self->{_configure_args} =~ m!nginx version: nginx/([0-9.]+)!;

	my @v = split(/\./, $1);
	my ($n, $v);

	for $n (split(/\./, $need)) {
		$v = shift @v || 0;
		return 0 if $n > $v;
		return 1 if $v > $n;
	}

	return 1;
}

sub has_daemon($) {
	my ($self, $daemon) = @_;

	if ($^O eq 'MSWin32') {
		`for %i in ($daemon.exe) do \@echo | set /p x=%~\$PATH:i`
			or Test::More::plan(skip_all => "$daemon not found");
		return $self;
	}

	if ($^O eq 'solaris') {
		Test::More::plan(skip_all => "$daemon not found")
			unless `command -v $daemon`;
		return $self;
	}

	Test::More::plan(skip_all => "$daemon not found")
		unless `which $daemon`;

	return $self;
}

sub try_run($$) {
	my ($self, $message) = @_;

	eval {
		open OLDERR, ">&", \*STDERR; close STDERR;
		$self->run();
		open STDERR, ">&", \*OLDERR;
	};

	return $self unless $@;

	if ($ENV{TEST_NGINX_VERBOSE}) {
		my $path = $self->{_configure_args} =~ m!--error-log-path=(\S+)!
			? $1 : 'logs/error.log';
		$path = "$self->{_testdir}/$path" if index($path, '/');

		open F, '<', $path or die "Can't open $path: $!";
		log_core($_) while (<F>);
		close F;
	}

	Test::More::plan(skip_all => $message);
	return $self;
}

sub plan($) {
	my ($self, $plan) = @_;

	Test::More::plan(tests => $plan + 2);

	return $self;
}

sub todo_alerts() {
	my ($self) = @_;

	$self->{_alerts} = 0;

	return $self;
}

sub run(;$) {
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
		exec($NGINX, '-p', "$testdir/", '-c', 'nginx.conf', @globals),
			or die "Unable to exec(): $!\n";
	}

	# wait for nginx to start

	$self->waitforfile("$testdir/nginx.pid", $pid)
		or die "Can't start nginx";

	for (1 .. 50) {
		last if $^O ne 'MSWin32';
		last if $self->read_file('error.log') =~ /create thread/;
		select undef, undef, undef, 0.1;
	}

	$self->{_started} = 1;
	return $self;
}

sub port {
	my ($num, %opts) = @_;
	my ($sock, $lock, $port);

	goto done if defined $ports{$num};

	my $socket = sub {
		IO::Socket::INET->new(
			Proto => 'tcp',
			LocalAddr => '127.0.0.1:' . shift,
			Listen => 1,
			Reuse => ($^O ne 'MSWin32'),
		);
	};

	my $socketl = sub {
		IO::Socket::INET->new(
			Proto => 'udp',
			LocalAddr => '127.0.0.1:' . shift,
		);
	};

	($socket, $socketl) = ($socketl, $socket) if $opts{udp};

	$port = $num;

	for (1 .. 10) {
		$port = int($port / 500) * 500 + int(rand(500)) unless $_ == 1;

		$lock = $socketl->($port) or next;
		$sock = $socket->($port) and last;
	}

	die "Port limit exceeded" unless defined $lock and defined $sock;

	$ports{$num} = {
		port => $port,
		socket => $lock
	};

done:
	return $ports{$num}{socket} if $opts{socket};
	return $ports{$num}{port};
}

sub dump_config() {
	my ($self) = @_;

	my $testdir = $self->{_testdir};

	my @globals = $self->{_test_globals} ?
		() : ('-g', "pid $testdir/nginx.pid; "
		. "error_log $testdir/error.log debug;");
	my $command = "$NGINX -T -p $testdir/ -c nginx.conf "
		. join(' ', @globals);

	return qx/$command 2>&1/;
}

sub waitforfile($;$) {
	my ($self, $file, $pid) = @_;
	my $exited;

	# wait for file to appear
	# or specified process to exit

	for (1 .. 50) {
		return 1 if -e $file;
		return 0 if $exited;
		$exited = waitpid($pid, WNOHANG) != 0 if $pid;
		select undef, undef, undef, 0.1;
	}

	return undef;
}

sub waitforsocket($) {
	my ($self, $peer) = @_;

	# wait for socket to accept connections

	for (1 .. 50) {
		my $s = IO::Socket::INET->new(
			Proto => 'tcp',
			PeerAddr => $peer
		);

		return 1 if defined $s;

		select undef, undef, undef, 0.1;
	}

	return undef;
}

sub reload() {
	my ($self) = @_;

	return $self unless $self->{_started};

	my $pid = $self->read_file('nginx.pid');

	if ($^O eq 'MSWin32') {
		my $testdir = $self->{_testdir};
		my @globals = $self->{_test_globals} ?
			() : ('-g', "pid $testdir/nginx.pid; "
			. "error_log $testdir/error.log debug;");
		system($NGINX, '-p', $testdir, '-c', "nginx.conf",
			'-s', 'reload', @globals) == 0
			or die "system() failed: $?\n";

	} else {
		kill 'HUP', $pid;
	}

	return $self;
}

sub stop() {
	my ($self) = @_;

	return $self unless $self->{_started};

	my $pid = $self->read_file('nginx.pid');

	if ($^O eq 'MSWin32') {
		my $testdir = $self->{_testdir};
		my @globals = $self->{_test_globals} ?
			() : ('-g', "pid $testdir/nginx.pid; "
			. "error_log $testdir/error.log debug;");
		system($NGINX, '-p', $testdir, '-c', "nginx.conf",
			'-s', 'stop', @globals) == 0
			or die "system() failed: $?\n";

	} else {
		kill 'QUIT', $pid;
	}

	waitpid($pid, 0);

	$self->{_started} = 0;

	return $self;
}

sub stop_daemons() {
	my ($self) = @_;

	while ($self->{_daemons} && scalar @{$self->{_daemons}}) {
		my $p = shift @{$self->{_daemons}};
		kill $^O eq 'MSWin32' ? 9 : 'TERM', $p;
		waitpid($p, 0);
	}

	return $self;
}

sub read_file($) {
	my ($self, $name) = @_;
	local $/;

	open F, '<', $self->{_testdir} . '/' . $name
		or die "Can't open $name: $!";
	my $content = <F>;
	close F;

	return $content;
}

sub write_file($$) {
	my ($self, $name, $content) = @_;

	open F, '>' . $self->{_testdir} . '/' . $name
		or die "Can't create $name: $!";
	binmode F;
	print F $content;
	close F;

	return $self;
}

sub write_file_expand($$) {
	my ($self, $name, $content) = @_;

	$content =~ s/%%TEST_GLOBALS%%/$self->test_globals()/gmse;
	$content =~ s/%%TEST_GLOBALS_HTTP%%/$self->test_globals_http()/gmse;
	$content =~ s/%%TESTDIR%%/$self->{_testdir}/gms;

	$content =~ s/127\.0\.0\.1:(8\d\d\d)/'127.0.0.1:' . port($1)/gmse;

	$content =~ s/%%PORT_(\d+)%%/port($1)/gmse;
	$content =~ s/%%PORT_(\d+)_UDP%%/port($1, udp => 1)/gmse;

	return $self->write_file($name, $content);
}

sub run_daemon($;@) {
	my ($self, $code, @args) = @_;

	my $pid = fork();
	die "Can't fork daemon: $!\n" unless defined $pid;

	if ($pid == 0) {
		if (ref($code) eq 'CODE') {
			$code->(@args);
			exit 0;
		} else {
			exec($code, @args);
			exit 0;
		}
	}

	$self->{_daemons} = [] unless defined $self->{_daemons};
	push @{$self->{_daemons}}, $pid;

	return $self;
}

sub testdir() {
	my ($self) = @_;
	return $self->{_testdir};
}

sub test_globals() {
	my ($self) = @_;

	return $self->{_test_globals}
		if defined $self->{_test_globals};

	my $s = '';

	$s .= "pid $self->{_testdir}/nginx.pid;\n";
	$s .= "error_log $self->{_testdir}/error.log debug;\n";

	$s .= $ENV{TEST_NGINX_GLOBALS}
		if $ENV{TEST_NGINX_GLOBALS};

	$s .= $self->test_globals_modules();
	$s .= $self->test_globals_perl5lib() if $s !~ /env PERL5LIB/;

	$self->{_test_globals} = $s;
}

sub test_globals_modules() {
	my ($self) = @_;

	my $modules = $ENV{TEST_NGINX_MODULES};

	if (!defined $modules) {
		my ($volume, $dir) = File::Spec->splitpath($NGINX);
		$modules = File::Spec->catpath($volume, $dir, '');
	}

	$modules = File::Spec->rel2abs($modules);
	$modules =~ s!\\!/!g if $^O eq 'MSWin32';

	my $s = '';

	$s .= "load_module $modules/ngx_http_geoip_module.so;\n"
		if $self->has_module('http_geoip\S+=dynamic');

	$s .= "load_module $modules/ngx_http_image_filter_module.so;\n"
		if $self->has_module('image_filter\S+=dynamic');

	$s .= "load_module $modules/ngx_http_perl_module.so;\n"
		if $self->has_module('perl\S+=dynamic');

	$s .= "load_module $modules/ngx_http_xslt_filter_module.so;\n"
		if $self->has_module('xslt\S+=dynamic');

	$s .= "load_module $modules/ngx_mail_module.so;\n"
		if $self->has_module('mail=dynamic');

	$s .= "load_module $modules/ngx_stream_module.so;\n"
		if $self->has_module('stream=dynamic');

	$s .= "load_module $modules/ngx_stream_geoip_module.so;\n"
		if $self->has_module('stream_geoip\S+=dynamic');

	return $s;
}

sub test_globals_perl5lib() {
	my ($self) = @_;

	return '' unless $self->has_module('perl');

	my ($volume, $dir) = File::Spec->splitpath($NGINX);
	my $objs = File::Spec->catpath($volume, $dir, '');

	$objs = File::Spec->rel2abs($objs);
	$objs =~ s!\\!/!g if $^O eq 'MSWin32';

	return "env PERL5LIB=$objs/src/http/modules/perl:"
		. "$objs/src/http/modules/perl/blib/arch;\n";
}

sub test_globals_http() {
	my ($self) = @_;

	return $self->{_test_globals_http}
		if defined $self->{_test_globals_http};

	my $s = '';

	$s .= "root $self->{_testdir};\n";
	$s .= "access_log $self->{_testdir}/access.log;\n";
	$s .= "client_body_temp_path $self->{_testdir}/client_body_temp;\n";

	$s .= "fastcgi_temp_path $self->{_testdir}/fastcgi_temp;\n"
		if $self->has_module('fastcgi');

	$s .= "proxy_temp_path $self->{_testdir}/proxy_temp;\n"
		if $self->has_module('proxy');

	$s .= "uwsgi_temp_path $self->{_testdir}/uwsgi_temp;\n"
		if $self->has_module('uwsgi');

	$s .= "scgi_temp_path $self->{_testdir}/scgi_temp;\n"
		if $self->has_module('scgi');

	$s .= $ENV{TEST_NGINX_GLOBALS_HTTP}
		if $ENV{TEST_NGINX_GLOBALS_HTTP};

	$self->{_test_globals_http} = $s;
}

###############################################################################

sub log_core {
	return unless $ENV{TEST_NGINX_VERBOSE};
	my ($prefix, $msg) = @_;
	($prefix, $msg) = ('', $prefix) unless defined $msg;
	$prefix .= ' ' if length($prefix) > 0;

	if (length($msg) > 2048) {
		$msg = substr($msg, 0, 2048)
			. "(...logged only 2048 of " . length($msg)
			. " bytes)";
	}

	$msg =~ s/^/# $prefix/gm;
	$msg =~ s/([^\x20-\x7e])/sprintf('\\x%02x', ord($1)) . (($1 eq "\n") ? "\n" : '')/gmxe;
	$msg .= "\n" unless $msg =~ /\n\Z/;
	print $msg;
}

sub log_out {
	log_core('>>', @_);
}

sub log_in {
	log_core('<<', @_);
}

###############################################################################

sub http_get($;%) {
	my ($url, %extra) = @_;
	return http(<<EOF, %extra);
GET $url HTTP/1.0
Host: localhost

EOF
}

sub http_head($;%) {
	my ($url, %extra) = @_;
	return http(<<EOF, %extra);
HEAD $url HTTP/1.0
Host: localhost

EOF
}

sub http($;%) {
	my ($request, %extra) = @_;

	my $s = http_start($request, %extra);

	return $s if $extra{start} or !defined $s;
	return http_end($s);
}

sub http_start($;%) {
	my ($request, %extra) = @_;
	my $s;

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(8);

		$s = $extra{socket} || IO::Socket::INET->new(
			Proto => 'tcp',
			PeerAddr => '127.0.0.1:' . port(8080)
		)
			or die "Can't connect to nginx: $!\n";

		log_out($request);
		$s->print($request);

		select undef, undef, undef, $extra{sleep} if $extra{sleep};
		return '' if $extra{aborted};

		if ($extra{body}) {
			log_out($extra{body});
			$s->print($extra{body});
		}

		alarm(0);
	};
	alarm(0);
	if ($@) {
		log_in("died: $@");
		return undef;
	}

	return $s;
}

sub http_end($;%) {
	my ($s) = @_;
	my $reply;

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(8);

		local $/;
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

###############################################################################

sub http_gzip_request {
	my ($url) = @_;
	my $r = http(<<EOF);
GET $url HTTP/1.1
Host: localhost
Connection: close
Accept-Encoding: gzip

EOF
}

sub http_content {
	my ($text) = @_;

	return undef if !defined $text;

	if ($text !~ /(.*?)\x0d\x0a?\x0d\x0a?(.*)/ms) {
		return undef;
	}

	my ($headers, $body) = ($1, $2);

	if ($headers !~ /Transfer-Encoding: chunked/i) {
		return $body;
	}

	my $content = '';
	while ($body =~ /\G\x0d?\x0a?([0-9a-f]+)\x0d\x0a?/gcmsi) {
		my $len = hex($1);
		$content .= substr($body, pos($body), $len);
		pos($body) += $len;
	}

	return $content;
}

sub http_gzip_like {
	my ($text, $re, $name) = @_;

	SKIP: {
		eval { require IO::Uncompress::Gunzip; };
		Test::More::skip(
			"IO::Uncompress::Gunzip not installed", 1) if $@;

		my $in = http_content($text);
		my $out;

		IO::Uncompress::Gunzip::gunzip(\$in => \$out);

		Test::More->builder->like($out, $re, $name);
	}
}

###############################################################################

1;

###############################################################################
