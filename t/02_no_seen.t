#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Data::Dumper;
use Prime::Watched;
use Scalar::Util 'looks_like_number';

SKIP: {
    diag('Set AMAZON_USER and AMAZON_PASS to run this test');
    skip if !$ENV{AMAZON_USER};

    my $prime = Prime::Watched->new({
        username => $ENV{AMAZON_USER}, # required
        password => $ENV{AMAZON_PASS}, # required
        pages => 1,                    # default = 10
        already_seen => {},            # default {}
        per_show_callback => sub {
            my ($show_id, $season, $episodes) = @_;
            ok($show_id, 'Show ID passed to callback');
            ok($season, 'Show season # passed to callback');
            ok(looks_like_number($season), 'Season is a number');
            ok(@$episodes, 'List of episodes passed to callback');
#            diag(Dumper($episodes));
            # Update Trakt or similar
        },                             # no default
        normalise_names   => sub {
            my ($name) = @_;
            # return $name string back somehow normalised
            return $name;
        },
                                    });
    my $eps = $prime->get_watched();
    ok(%$eps, 'Hashref of episode data returned from get_watched');
}
done_testing;
