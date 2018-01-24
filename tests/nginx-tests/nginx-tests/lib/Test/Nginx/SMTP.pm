package Test::Nginx::SMTP;

# (C) Maxim Dounin

# Module for nginx smtp tests.

###############################################################################

use warnings;
use strict;

use Test::More qw//;
use IO::Socket;
use Socket qw/ CRLF /;

use Test::Nginx;

sub new {
	my $self = {};
	bless $self, shift @_;

	$self->{_socket} = IO::Socket::INET->new(
		Proto => "tcp",
		PeerAddr => "127.0.0.1:8025",
		@_
	)
		or die "Can't connect to nginx: $!\n";

	if ({@_}->{'SSL'}) {
		require IO::Socket::SSL;
		IO::Socket::SSL->start_SSL($self->{_socket}, @_)
			or die $IO::Socket::SSL::SSL_ERROR . "\n";
	}

	$self->{_socket}->autoflush(1);

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

sub read {
	my ($self) = @_;
	my $socket = $self->{_socket};
	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		alarm(3);
		while (<$socket>) {
			log_in($_);
			next if m/^\d\d\d-/;
			last;
		}
		alarm(0);
	};
	alarm(0);
	if ($@) {
		log_in("died: $@");
		return undef;
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

###############################################################################

sub smtp_test_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:8026',
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	while (my $client = $server->accept()) {
		$client->autoflush(1);
		print $client "220 fake esmtp server ready" . CRLF;

		while (<$client>) {
			Test::Nginx::log_core('||', $_);

			if (/^quit/i) {
				print $client '221 quit ok' . CRLF;
			} elsif (/^(ehlo|helo)/i) {
				print $client '250 hello ok' . CRLF;
			} elsif (/^rset/i) {
				print $client '250 rset ok' . CRLF;
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
