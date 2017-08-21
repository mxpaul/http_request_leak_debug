#!/usr/bin/env perl
use strict;
use warnings;

use Data::Dumper;

use EV;
use AnyEvent;
use AnyEvent::HTTP;
use Carp;
use Scalar::Util qw(weaken);
use Devel::Leak;
#use Devel::FindRef;
use Guard;

$AnyEvent::HTTP::USERAGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2227.1 Safari/537.36';
#$AnyEvent::HTTP::MAX_PER_HOST = 1;

sub curr_vsize {
	my $vsize = do {open my $f, '<', "/proc/$$/stat"; (split(/\s/, <$f>))[22]};
}

sub gohttp {
	my $cb = pop or croak 'Need callback';
	my $i = shift or '<indef>';
	my $state = {cb => $cb};
	#$state->{die} = guard {AE::log error => 'Guard state %s', $i};
	#my $tguard = guard {AE::log error => 'Guard timer sub %s', $i};
	#my $hguard = guard {AE::log error => 'Guard http sub %s', $i};
	my $timeout = 0.05;
	$state->{timer} = AE::timer $timeout, 0, sub {
		#AE::log (error => 'timer %s' , $i);
		#undef $tguard;
		return unless ref $state eq 'HASH';
		my $cb = delete $state->{cb};
		for (keys %$state) {
			undef $state->{$_} if defined $state->{$_};
			delete $state->{$_};
		}
		undef $state;
		return unless $cb;
		$cb->(sprintf('request timeout: %gs', $timeout));
	};
	#$state->{guard} = http_request(GET =>'http://127.0.0.1:52241/',
	$state->{guard} = http_request(GET =>'http://localhost.mail.ru:52241/',
		headers   => {},
		recurse   => 0,
		timeout   => 1,
		sub {
			#undef $tguard;
			#AE::log (error => 'callback %s' , $i);
			return unless ref $state eq 'HASH';
			my $cb = delete $state->{cb} or return;
			for (keys %$state) {
				undef $state->{$_} if defined $state->{$_};
				delete $state->{$_};
			}
			undef $state;
			my ($b, $hdr) = (shift, shift);
			$cb->(join( ' ', $hdr->{Status}, $hdr->{Reason}, 's='.length($b//'').'b'));
			undef $b, undef $hdr;
		}
	);
}

sub one_task { my $i = shift;
	my $cb = pop or croak 'Need callback';
	my $vsz_start = curr_vsize;
	gohttp($i, sub {
		my $msg = shift;
		my $vsz_end = curr_vsize;
		my $diff = $vsz_end - $vsz_start;
		warn sprintf("%05d: V=%.02fM/%+02db %s\n", $i, $vsz_start/1024/1024, $diff, $msg);
		$cb->();
	});
}

warn "Warming up...\n";
my $cv = AE::cv; $cv->begin;
for (1..20) { $cv->begin; gohttp('warmup', sub { $cv->end; });};
$cv->end; $cv->recv;
warn "Warming up complete\n";

my $running = 0;
my $i = 1;
my $work; $work = sub {
	return if $running >= 10;
	$running ++;
	one_task($i++, sub {
			$running --;
			goto &$work;
	});
};

$SIG{INT} = sub {EV::unloop};
#my $count = Devel::Leak::NoteSV(my $handle);
$work->();
EV::loop;
#Devel::Leak::CheckSV($handle);

