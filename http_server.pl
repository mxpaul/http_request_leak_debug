#!/usr/bin/env perl
use strict;
use warnings;

use Data::Dumper;

use EV;
use AnyEvent;
use AnyEvent::HTTP::Server;

my $http = AnyEvent::HTTP::Server->new(
	host => '127.0.0.1',
	port => 52241,
	cb => sub{ my $r = shift;
		AE::log error => 'GOT REQUEST: path=%s', $r->path;
		my $reply_time = rand() < 0.1 ? rand(1) + 1 : 0.001;
		my $t; $t = AE::timer $reply_time, 0, sub {
			undef $t;
			$r->reply(200, 'HELLO WORLD!'x4000);
		};
		return;
	}
);
$http->listen; $http->accept;
my $cv = AE::cv;
$SIG{INT} = $SIG{TERM} = sub {AE::log error => 'CTRL+C'; $cv->send};
AE::log error => 'Listening';
$cv->recv;
