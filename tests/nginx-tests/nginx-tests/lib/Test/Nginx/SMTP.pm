package Test::Nginx::SMTP;

# (C) Maxim Dounin

# Module for nginx smtp tests.

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

	$self->{_socket} = IO::Socket::INET->new(
		Proto => "tcp",
		PeerAddr => "127.0.0.1:" . port(8025),
		@_
	)
		or die "Can't connect to nginx: $!\n";

	if ({@_}->{'SSL'}) {
		require IO::Socket::SSL;
		IO::Socket::SSL->start_SSL($self->{_socket}, @_)
			or die $IO::Socket::SSL::SSL_ERROR . "\n";
	}

	$self->{_socket}->autoflush(1);
	$self->{_read_buffer} = '';

	return $self;
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
		$socket->blocking(1);
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
		next if m/^\d\d\d-/;
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
	Test::More->builder->like($self->read(), qr/^2\d\d /, @_);
}

sub authok {
	my $self = shift;
	Test::More->builder->like($self->read(), qr/^235 /, @_);
}

sub can_read {
	my ($self, $timo) = @_;
	IO::Select->new($self->{_socket})->can_read($timo || 3);
}

###############################################################################

sub smtp_test_daemon {
	my ($port) = @_;
	my $proxy_protocol;

	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:' . ($port || port(8026)),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	while (my $client = $server->accept()) {
		$client->autoflush(1);
		print $client "220 fake esmtp server ready" . CRLF;

		$proxy_protocol = '';

		while (<$client>) {
			Test::Nginx::log_core('||', $_);

			if (/^quit/i) {
				print $client '221 quit ok' . CRLF;
			} elsif (/^(ehlo|helo)/i) {
				print $client '250 hello ok' . CRLF;
			} elsif (/^rset/i) {
				print $client '250 rset ok' . CRLF;
			} elsif (/^auth plain/i) {
				print $client '235 auth ok' . CRLF;
			} elsif (/^mail from:[^@]+$/i) {
				print $client '500 mail from error' . CRLF;
			} elsif (/^mail from:/i) {
				print $client '250 mail from ok' . CRLF;
			} elsif (/^rcpt to:[^@]+$/i) {
				print $client '500 rcpt to error' . CRLF;
			} elsif (/^rcpt to:/i) {
				print $client '250 rcpt to ok' . CRLF;
			} elsif (/^xclient/i) {
				print $client '220 xclient ok' . CRLF;
			} elsif (/^proxy/i) {
				$proxy_protocol = $_;
			} elsif (/^xproxy/i) {
				print $client '211 ' . $proxy_protocol . CRLF;
			} else {
				print $client "500 unknown command" . CRLF;
			}
		}

		close $client;
	}
}

###############################################################################

1;

###############################################################################
