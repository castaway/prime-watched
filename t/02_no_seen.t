#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Data::Dumper;
use Prime::Watched;

if(!$ENV{AMAZON_USER}) {
    diag('Set AMAZON_USER and AMAZON_PASS to run this test');
    done_testing;
    exit;
}

my $prime = Prime::Watched->new({
    username => $ENV{AMAZON_USER}, # required
    password => $ENV{AMAZON_PASS}, # required
    pages => 1,                    # default = 10
    already_seen => {},            # default {}
    per_show_callback => sub {
        my ($show_id, $season, $episodes) = @_;
        diag(Dumper($episodes));
        # Update Trakt or similar
    },                             # no default
    normalise_names   => sub {
        my ($name) = @_;
        # return $name string back somehow normalised
        return $name;
    },
                                });
$prime->get_watched();

done_testing;
