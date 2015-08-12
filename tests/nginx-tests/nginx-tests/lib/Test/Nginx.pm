package Test::Nginx;

# (C) Maxim Dounin

# Generic module for nginx tests.

###############################################################################

use warnings;
use strict;

use base qw/ Exporter /;

our @EXPORT = qw/ log_in log_out http http_get http_head /;
our @EXPORT_OK = qw/ http_gzip_request http_gzip_like http_start http_end /;
our %EXPORT_TAGS = (
	gzip => [ qw/ http_gzip_request http_gzip_like / ]
);

###############################################################################

use File::Path qw/ rmtree /;
use File::Temp qw/ tempdir /;
use IO::Socket;
use POSIX qw/ waitpid WNOHANG /;
use Socket qw/ CRLF /;
use Test::More qw//;

###############################################################################

our $NGINX = defined $ENV{TEST_NGINX_BINARY} ? $ENV{TEST_NGINX_BINARY}
	: '../nginx/objs/nginx';

sub new {
	my $self = {};
	bless $self;

	$self->{_pid} = $$;

	$self->{_testdir} = tempdir(
		'nginx-test-XXXXXXXXXX',
		TMPDIR => 1,
		CLEANUP => not $ENV{TEST_NGINX_LEAVE}
	)
		or die "Can't create temp directory: $!\n";
	$self->{_testdir} =~ s!\\!/!g if $^O eq 'MSWin32';
	$self->{_dso_module} = ();
	mkdir "$self->{_testdir}/logs"
		or die "Can't create logs directory: $!\n";

	return $self;
}

sub DESTROY {
	my ($self) = @_;
	local $?;

	return if $self->{_pid} != $$;
	$self->stop();
	$self->stop_daemons();
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
		Test::More::plan(skip_all => "$feature not compiled in")
			unless $self->has_module($feature);
	}

	return $self;
}

sub set_dso($;) {
	my ($self, $module_name, $module_path) = @_;

	$self->{_dso_module}{$module_name} = $module_path;
}

sub has_module($) {
	my ($self, $feature) = @_;

	my %regex = (
		sni	=> 'TLS SNI support enabled',
		mail	=> '--with-mail(?!\S)',
		flv	=> '--with-http_flv_module',
		perl	=> '--with-http_perl_module',
		auth_request
			=> '--with-http_auth_request_module',
		charset	=> '(?s)^(?!.*--without-http_charset_module)',
		gzip	=> '(?s)^(?!.*--without-http_gzip_module)',
		ssi	=> '(?s)^(?!.*--without-http_ssi_module)',
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
		reqstat
			=> '(?s)^(?!.*--without-http_reqstat_module)',
		upstream_least_conn
			=> '(?s)^(?!.*--without-http_upstream_least_conn_mod)',
		upstream_keepalive
			=> '(?s)^(?!.*--without-http_upstream_keepalive_modu)',
		http	=> '(?s)^(?!.*--without-http(?!\S))',
		cache	=> '(?s)^(?!.*--without-http-cache)',
		pop3	=> '(?s)^(?!.*--without-mail_pop3_module)',
		imap	=> '(?s)^(?!.*--without-mail_imap_module)',
		smtp	=> '(?s)^(?!.*--without-mail_smtp_module)',
		pcre	=> '(?s)^(?!.*--without-pcre)',
		split_clients
			=> '(?s)^(?!.*--without-http_split_clients_module)',
	);

	my $re = $regex{$feature};
	$re = $feature if !defined $re;

	$self->{_configure_args} = `$NGINX -V 2>&1`
		if !defined $self->{_configure_args};

	return ($self->{_configure_args} =~ $re or $self->{_configure_args} =~ '--enable-mods-static=all') ? 1 : 0;
}

sub has_version($) {
	my ($self, $need) = @_;

	$self->{_configure_args} = `$NGINX -V 2>&1`
		if !defined $self->{_configure_args};

	$self->{_configure_args} =~ m!nginx/([0-9.]+)!;

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
		Test::More::plan(skip_all => "win32");
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

        $self->run();

	eval {
		open OLDERR, ">&", \*STDERR; close STDERR;
		$self->run();
		open STDERR, ">&", \*OLDERR;
	};

	Test::More::plan(skip_all => $message) if $@;
	return $self;
}

sub plan($) {
	my ($self, $plan) = @_;

	Test::More::plan(tests => $plan);

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
		exec($NGINX, '-p', $testdir, '-c', 'nginx.conf', @globals),
			or die "Unable to exec(): $!\n";
	}

	# wait for nginx to start

	$self->waitforfile("$testdir/nginx.pid", $pid)
		or die "Can't start nginx";

	$self->{_started} = 1;
	return $self;
}

sub waitforfile($;$) {
	my ($self, $file, $pid) = @_;
	my $exited;

	# wait for file to appear
	# or specified process to exit

	for (1 .. 30) {
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

	for (1 .. 30) {
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

	local $/;
	open F, '<' . $self->{_testdir} . '/nginx.pid'
		or die "Can't open nginx.pid: $!";
	my $pid = <F>;
	close F;

	if ($^O eq 'MSWin32') {
		my $testdir = $self->{_testdir};
		my @globals = $self->{_test_globals} ?
			() : ('-g', "pid $testdir/nginx.pid; "
			. "error_log $testdir/error.log debug;");
		system($NGINX, '-c', "$testdir/nginx.conf", '-s', 'reload',
			@globals) == 0
			or die "system() failed: $?\n";

	} else {
		kill 'HUP', $pid;
	}

	sleep(1);

	return $self;
}

sub stop() {
	my ($self) = @_;

	return $self unless $self->{_started};

	local $/;
	open F, '<' . $self->{_testdir} . '/nginx.pid'
		or die "Can't open nginx.pid: $!";
	my $pid = <F>;
	close F;

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

    open F, '<', $self->{_testdir} . '/' . $name or die "Can't open $name: $!";
    my $content = <F>;
    close F;
    
    return $content;
}

sub write_file($$) {
	my ($self, $name, $content) = @_;

	open F, '>' . $self->{_testdir} . '/' . $name
		or die "Can't create $name: $!";
	print F $content;
	close F;

	return $self;
}

sub write_file_expand($$) {
	my ($self, $name, $content) = @_;

	$content =~ s/%%TEST_GLOBALS%%/$self->test_globals()/gmse;
	$content =~ s/%%TEST_GLOBALS_DSO%%/$self->test_globals_dso()/gmse;
	$content =~ s/%%TEST_GLOBALS_HTTP%%/$self->test_globals_http()/gmse;
	$content =~ s/%%TESTDIR%%/$self->{_testdir}/gms;

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
	$self->{_test_globals} = $s;
}

sub test_globals_dso() {
	my ($self) = @_;

	return "" unless defined $ENV{TEST_NGINX_DSO};

	return $self->{_test_globals_dso} if defined $self->{_test_globals_dso};

	my $s = '';

	$s .= "dso {\n";
	if (defined $ENV{NGINX_DSO_PATH}) {
		$s .= "path $ENV{NGINX_DSO_PATH};\n";
	}

	while ( my ($key, $value) = each(%{$self->{_dso_module}}) ) {
		$s .= "load $key $value;\n";
	}
	$s .= "}\n";

	$self->{_test_globals_dso} = $s;
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
		alarm(5);

		$s = $extra{socket} || IO::Socket::INET->new(
			Proto => 'tcp',
			PeerAddr => '127.0.0.1:8080'
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
		alarm(5);

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
		Test::More->builder->skip(
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
