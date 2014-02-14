package Test::Nginx::POP3;

# (C) Maxim Dounin

# Module for nginx pop3 tests.

###############################################################################

use warnings;
use strict;

use Test::More qw//;
use IO::Socket;
use Socket qw/ CRLF /;

use Test::Nginx;

use base qw/ IO::Socket::INET /;

sub new {
	my $class = shift;

	my $self = return $class->SUPER::new(
		Proto => "tcp",
		PeerAddr => "127.0.0.1:8110",
		@_
	)
		or die "Can't connect to nginx: $!\n";

	$self->autoflush(1);

	return $self;
}

sub send {
	my ($self, $cmd) = @_;
	log_out($cmd);
	$self->print($cmd . CRLF);
}

sub read {
	my ($self) = @_;
	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		alarm(3);
		while (<$self>) {
			log_in($_);
			# XXX
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
	Test::More->builder->like($self->read(), qr/^\+OK/, @_);
}

###############################################################################

sub pop3_test_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:8111',
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
