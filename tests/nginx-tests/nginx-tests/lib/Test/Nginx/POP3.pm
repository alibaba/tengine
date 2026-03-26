package Test::Nginx::POP3;

# (C) Maxim Dounin

# Module for nginx pop3 tests.

###############################################################################

use warnings;
use strict;

use Test::More qw//;
use IO::Select;
use IO::Socket;
use Socket qw/ CRLF /;

use Test::Nginx;

sub new {
	my $self = {};
	bless $self, shift @_;

	my $port = {@_}->{'SSL'} ? 8995 : 8110;

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(8);

		$self->{_socket} = IO::Socket::INET->new(
			Proto => "tcp",
			PeerAddr => "127.0.0.1:" . port($port),
			@_
		)
			or die "Can't connect to nginx: $!\n";

		if ({@_}->{'SSL'}) {
			require IO::Socket::SSL;
			IO::Socket::SSL->start_SSL(
				$self->{_socket},
				SSL_verify_mode =>
					IO::Socket::SSL::SSL_VERIFY_NONE(),
				@_
			)
				or die $IO::Socket::SSL::SSL_ERROR . "\n";

			my $s = $self->{_socket};
			log_in("ssl cipher: " . $s->get_cipher());
			log_in("ssl cert: " . $s->peer_certificate('issuer'));
		}

		alarm(0);
	};
	alarm(0);
	if ($@) {
		log_in("died: $@");
	}

	$self->{_socket}->autoflush(1);
	$self->{_read_buffer} = '';

	return $self;
}

sub DESTROY {
	my $self = shift;
	$self->{_socket}->close();
}

sub eof {
	my $self = shift;
	return $self->{_socket}->eof();
}

sub print {
	my ($self, $cmd) = @_;
	log_out($cmd);
	$self->{_socket}->print($cmd);
}

sub send {
	my ($self, $cmd) = @_;
	log_out($cmd);
	$self->{_socket}->print($cmd . CRLF);
}

sub getline {
	my ($self) = @_;
	my $socket = $self->{_socket};

	if ($self->{_read_buffer} =~ /^(.*?\x0a)(.*)/ms) {
		$self->{_read_buffer} = $2;
		return $1;
	}

	while (IO::Select->new($socket)->can_read(8)) {
		$socket->blocking(0);
		my $n = $socket->sysread(my $buf, 1024);
		my $again = !defined $n && $!{EWOULDBLOCK};
		$socket->blocking(1);
		next if $again;
		last unless $n;

		$self->{_read_buffer} .= $buf;

		if ($self->{_read_buffer} =~ /^(.*?\x0a)(.*)/ms) {
			$self->{_read_buffer} = $2;
			return $1;
		}
	};
}

sub read {
	my ($self) = @_;
	my $socket = $self->{_socket};

	while (defined($_ = $self->getline())) {
		log_in($_);
		last;
	}

	return $_;
}

sub check {
	my ($self, $regex, $name) = @_;
	Test::More->builder->like($self->read(), $regex, $name);
}

sub ok {
	my $self = shift;
	Test::More->builder->like($self->read(), qr/^\+OK/, @_);
}

sub can_read {
	my ($self, $timo) = @_;
	IO::Select->new($self->{_socket})->can_read($timo || 3);
}

sub socket {
	my ($self) = @_;
	$self->{_socket};
}

###############################################################################

sub pop3_test_daemon {
	my ($port) = @_;

	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:' . ($port || port(8111)),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	while (my $client = $server->accept()) {
		$client->autoflush(1);
		print $client "+OK fake pop3 server ready" . CRLF;

		while (<$client>) {
			if (/^quit/i) {
				print $client '+OK quit ok' . CRLF;
			} elsif (/^user test\@example.com/i) {
				print $client '+OK user ok' . CRLF;
			} elsif (/^pass secret/i) {
				print $client '+OK pass ok' . CRLF;
			} else {
				print $client "-ERR unknown command" . CRLF;
			}
		}

		close $client;
	}
}

###############################################################################

1;

###############################################################################
