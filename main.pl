#!/usr/bin/perl -w

########################################################################
#
# campaign-start-stop
# 
# Author: Dmitry Minaev, Five9 (dminaev@five9.com)
#
# Description: script calls Five9 API to start or stop campaigns listed
#	in campaigns.txt file.
########################################################################

use strict;
use warnings;

use SOAP::Lite; # +trace => 'debug'; # uncomment if you want to see API request/response
use Data::Dumper;
use Cwd;
use Text::CSV;

use constant WAIT_FOR_API_REQUEST => 1;

my $constants;

########################################################################
### Main execution goes here

eval { main(); };

if($@) {
	print $@;
}


########################################################################
### Main

sub main {

	# parse config file
	$constants = parse_config_file();

	# get type of run
	my $type = $ARGV[0] if defined $ARGV[0] ||
		die "Do you want to 'start' or 'stop' campaign? Please specify it as a first parameter to the script, e.g.\n#> main.pl start\n";

	# do we want to try force stop campaign?
	my $force = (defined($ARGV[1]) && ($ARGV[1] eq 'force' || $ARGV[1] eq 'f' || $ARGV[1] eq '1') ? 1 : 0);

	# prepare file
	my $filepath = $constants->{'SPOOL'}.'/'.$type."_campaigns.csv";
	my $csv = prepare_csv();
	open (CSV, ">", $filepath) || die "$!";

	my @headers = ("Campaign name", "Old state", "New state");
	$csv->combine(@headers);
	print CSV $csv->string;

	# initialize SOAP parameters
	my $client = initialize_SOAP();

	# get all the campaigns to start/stop
	my $campaigns = get_campaigns();

	# do the job
	foreach my $camp (@{$campaigns}) {

		my $campState = getCampaignState($client, $camp, WAIT_FOR_API_REQUEST);
		print "Campaign '" . $camp . "' is " . $campState if $constants->{'DEBUG'};

		my @row = ();
		push @row, $camp;
		push @row, $campState;

		if($type eq 'stop') {

			if($campState eq "RUNNING") {

				$campState = stop($client, $camp, $campState, $force);
				push @row, $campState;

			} else {

				print 'Campaign ' . $camp . ' is currently ' . $campState . '. Doing nothing with this campaign.' if $constants->{'DEBUG'};
				push @row, $campState;
			}

		} elsif ($type eq 'start') {

			if($campState ne "RUNNING") {

				$campState = start($client, $camp, $campState);
				push @row, $campState;

			} else {

				print 'Campaign ' . $camp . ' is currently ' . $campState . '. Doing nothing with this campaign.' if $constants->{'DEBUG'};
				push @row, $campState;
			}
		}

		$csv->combine(@row);
		print CSV $csv->string;
	} 

    close CSV;

	return $filepath;
}


########################################################################
### Functions

### read config file
sub parse_config_file {

	my %ret;

	my $filepath = Cwd::getcwd()."/config.txt";
	open(my $fh, '<:encoding(UTF-8)', $filepath)
	  or die "Could not open file '$filepath' $!";

	while (<$fh>) {
		chomp;                  # no newline
		s/#.*//;                # no comments
		s/^\s+//;               # no leading white
		s/\s+$//;               # no trailing white
		next unless length;     # anything left?
		my ($var, $value) = split(/\s*=\s*/, $_, 2);
		$ret{$var} = $value;
	}

	return \%ret;
}


sub prepare_csv {

	my $sep_char = shift;
	my $eol = shift;

	$sep_char = "," unless defined $sep_char;
	$eol = "\r\n" unless defined $eol;

    return Text::CSV->new ({
        'quote_char'          => '"',
        'escape_char'         => '"',
        'sep_char'            => $sep_char,
        'eol'                 => $eol,
        'quote_space'         => 0,
        'quote_null'          => 0,
        'always_quote'        => 0,
        'binary'              => 1,
        'keep_meta_info'      => 0,
        'allow_loose_quotes'  => 0,
        'allow_loose_escapes' => 0,
        'allow_whitespace'    => 1,
        'blank_is_undef'      => 0,
        'empty_is_undef'      => 0,
        'verbatim'            => 0,
        'auto_diag'           => 0,
    });
}


sub start {

	my ($client, $camp, $campState) = @_;

	print "Trying to start campaign " . $camp if $constants->{'DEBUG'};

	startCampaign($client, $camp);

	$campState = getCampaignState($client, $camp, WAIT_FOR_API_REQUEST);

#	my $iter = 0;
#	while ($campState ne "RUNNING" && $iter < WAIT_FOR_API_REQUEST) {
#		$campState = getCampaignState($client, $camp, 1);
#		print "Iteration #" . $iter . ". Campaign " . $camp . " is now " . $campState if $constants->{'DEBUG'};
#		$iter++;
#	}

	if($campState ne "RUNNING") {
		print 'Campaign ' . $camp . ' failed to start.' if $constants->{'DEBUG'};
	} else {
		print 'Campaign ' . $camp . ' has started.' if $constants->{'DEBUG'};
	}

	return $campState;
}


sub stop {

	my ($client, $camp, $campState, $force) = @_;

	print "Trying to stop campaign " . $camp if $constants->{'DEBUG'};

	stopCampaign($client, $camp);

	$campState = getCampaignState($client, $camp, WAIT_FOR_API_REQUEST);

#	my $iter = 0;
#	while ($campState ne "NOT_RUNNING" && $iter < WAIT_FOR_API_REQUEST) {
#		$campState = getCampaignState($client, $camp, 1);
#		print "Iteration #" . $iter . ". Campaign " . $camp . " is now " . $campState if $constants->{'DEBUG'};
#		$iter++;
#	}

	if($campState ne "NOT_RUNNING" && $force) {
		print 'Trying to force stop campaign ' . $camp if $constants->{'DEBUG'};
		forceStopCampaign($client, $camp);

		$campState = getCampaignState($client, $camp, WAIT_FOR_API_REQUEST);
		print "Campaign " . $camp . " is now " . $campState if $constants->{'DEBUG'};
	}

	if($campState ne "NOT_RUNNING") {
		print 'Campaign ' . $camp . ' failed to stop ' . ($force ? ' (even force stop failed!)' : '') if $constants->{'DEBUG'};
	} else {
		print 'Campaign ' . $camp . ' has stopped.' if $constants->{'DEBUG'};
	}

	return $campState;
}

sub get_campaigns {

	my @ret;

	my $filepath = Cwd::getcwd()."/campaigns.txt";
	open(my $fh, '<:encoding(UTF-8)', $filepath)
	  or die "Could not open file '$filepath' $!";

	while (<$fh>) {
		chomp;                  # no newline
		s/#.*//;                # no comments
		s/^\s+//;               # no leading white
		s/\s+$//;               # no trailing white
		next unless length;     # anything left?
		push @ret, $_;
	}

	return \@ret;
}

########################################################################
### initialize SOAP
sub initialize_SOAP {

	###
	### REQUIRED!!!
	### workaround for a bug in SOAP::Lite
	### https://rt.cpan.org/Public/Bug/Display.html?id=29505
	### http://stackoverflow.com/questions/24064945/perl-soaplite-request-not-setting-xmlnssoap-with-correct-value-on-axis2
	###
	$SOAP::Constants::PREFIX_ENV = 'SOAP-ENV';

	my $client = SOAP::Lite->new()
		->soapversion('1.2')
		->envprefix('soap12')
		->service($constants->{'BASEURI'}.$constants->{'FIVE9USERNAME'})
		->readable('true')
		->on_fault(
			sub {
				my($soap, $res) = @_;
				die (ref($res) ? $res->faultcode.": ".$res->faultstring : Dumper $soap->transport->status, "\n");
			}
		);

	$client->soapversion('1.2');

	#- Overriding the constant for SOAP 1.2
	$SOAP::Constants::DEFAULT_HTTP_CONTENT_TYPE = 'application/soap+xml';

	#- Pass Basic login/password authentication, override get_basic_credentials function
	sub SOAP::Transport::HTTP::Client::get_basic_credentials {
		my $u = $constants->{'FIVE9USERNAME'};
		my $p = $constants->{'FIVE9PASSWORD'};
		return $u => $p;
	}

	$client->soapversion('1.2');

	return $client;
}


sub stopCampaign {

	my ($client, $campaignName) = @_;

	$client->soapversion('1.2'); # MANDATORY

	$client->stopCampaign(
		$client,
		SOAP::Data->name('campaignName', $campaignName)
	);

	return 1;
}

sub forceStopCampaign {

	my ($client, $campaignName) = @_;

	$client->soapversion('1.2'); # MANDATORY

	$client->forceStopCampaign(
		$client,
		SOAP::Data->name('campaignName', $campaignName)
	);

	return 1;
}


sub startCampaign {

	my ($client, $campaignName) = @_;

	$client->soapversion('1.2'); # MANDATORY

	my $result;
	$result = $client->startCampaign(
		$client,
		SOAP::Data->name('campaignName', $campaignName)
	);

	return $result;
}

sub getCampaignState {

	my (  $client
		, $campaignName		# Name of campaign.
		, $waitUntilChange	# Optional duration in seconds to wait for changes. 
							# If omitted, the response is returned immediately.
	) = @_;

	$client->soapversion('1.2'); # MANDATORY

	my $waitUntilChange_parameter = (defined($waitUntilChange) ? SOAP::Data->name('waitUntilChange', $waitUntilChange) : undef);

	my $result;

	$result = $client->getCampaignState(
		$client,
		SOAP::Data->name('campaignName', $campaignName)
		, $waitUntilChange_parameter
	);

	return $result;
}

