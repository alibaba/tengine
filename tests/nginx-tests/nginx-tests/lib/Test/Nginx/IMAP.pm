package Test::Nginx::IMAP;

# (C) Maxim Dounin

# Module for nginx imap tests.

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
		PeerAddr => "127.0.0.1:8143",
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
	Test::More->builder->like($self->read(), qr/^\S+ OK/, @_);
}

###############################################################################

sub imap_test_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:8144',
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	while (my $client = $server->accept()) {
		$client->autoflush(1);
		print $client "* OK fake imap server ready" . CRLF;

		while (<$client>) {
			my $tag = '';

			$tag = $1 if m/^(\S+)/;
			s/^(\S+)\s+//;

			if (/^logout/i) {
				print $client $tag . ' OK logout ok' . CRLF;
			} elsif (/^login /i) {
				print $client $tag . ' OK login ok' . CRLF;
			} else {
				print $client $tag . ' ERR unknown command' . CRLF;
			}
                }

		close $client;
	}
}

###############################################################################

1;

###############################################################################
