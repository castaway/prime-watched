package Prime::Watched;

=head1 NAME

Prime::Watched - Exatrct your watched TV / Film data from your Amazon Prime account

=head1 SYNOPSIS

    use Prime::Watched;
    my $prime = Prime::Watched->new({
        username => 'xxx',            # required
        password => 'yyy',            # required
        pages => 2,                   # default = 10
        already_seen => {},           # default {}
        mech_arguments => {
           autoclose => 1,
           launch_exe => '/usr/bin/google-chrome-stable',
           host => 'localhost',

           background_networking => 0,
           autodie => 1,
           report_js_errors => 1,
           incognito => 1,
        },                             # these are the defaults
        per_show_callback => sub {
            my ($show_id, $season, $episodes) = @_;
            # Update Trakt or similar
        },                             # no default
        normalise_names   => sub {
            my ($name) = @_;
            # return $name string back somehow normalised
        },
    });
    $prime->get_watched();

=head1 DESCRIPTION

Prime::Watched uses WWW::Mechanize::Chrome to retrieve the user's
"Watched shows history" from Amazon Prime. It fires the user supplied
callback for each different show the user has watched, supplying all
of the episodes that have been fully (at least 90%) watched.

NOTE: As there is no API for this information, username + password are
required to login, these are used to POST to the login form. Do not
use this software if you if you have any doubts about it.

UNSTABLE: On some runs chrome errors out, I have yet to discover why,
on subsequent runs it works fine. Help with this issue would be
appreciated.

=head1 ATTRIBUTES

=cut

use 5.20.0;
use strictures 2;

# required by WWW::Mechanize::Chrome
use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR
use WWW::Mechanize::Chrome;
use HTML::TreeBuilder;

use Moo;

our $VERSION = '0.01';

=head2 username

Amazon login username, used once to login.

=head2 password

Amazon login password, used once to login.

=cut

# amazon login
has username => ( is => 'ro' );
has password => ( is => 'ro' );

=head2 pages

Number of "watch history" pages to read, defaults to 10.

=cut

# number of pages to read
has pages => ( is => 'ro', default => sub { 10 }, );

=head2 already_seen

Passed in hashref of already known shows+episodes, used to avoid
parsing pages / episodes that we've already seen.

A HashRef with normalised names of shows as keys, containing values
matching L<https://trakt.tv> show objects, see
L<https://trakt.docs.apiary.io/#introduction/standard-media-objects/show>.

=cut

# already seen items (defaults to trakt watched/shows format)
has already_seen => ( is => 'ro', default => sub { {}; });

=head2 mech_arguments

Set of arguments to start L<WWW::Mechanize::Chrome> with, see
L</SYNOPSIS> for defaults.

=cut

has mech_arguments => ( is => 'rw',
                        default => sub {
                            {
                                autoclose => 1,
                                launch_exe => '/usr/bin/google-chrome-stable',
                                host => 'localhost',
                                
                                background_networking => 0,
                                autodie => 1,
                                report_js_errors => 1,
                                incognito => 1,
                            };
                        });


=head2 per_show_callback

Code reference which will be called for each separate show/season
combination we find, with arguments:

=over

=item $show_slug

Taken from the L</already_seen> data if passed in, generated if not.

=item $season

As a number

=item $episides

As an ArrayRef of HashRefs, each episode has a "num" (numerical id) and a "title".

=back

=cut

# coderef to run with data from each page
has per_show_callback => ( is => 'ro', default => sub {
                  } );


=head2 normalise_names

A coderef for removing extra symbols or data in names, in order to
match them with the names in the L</already_seen> data. Takes a string
and returns a string.

=cut

# coderef to normalise show names
has normalise_names => ( is => 'rw', required => 1 );


has _watched_uri => ( is => 'ro', default => sub { 'https://www.amazon.co.uk/gp/yourstore/iyr/ref=pd_ys_iyr_edit_watched?ie=UTF8&collection=watched'; } );

has _chrome_mech => ( is => 'lazy',
                      default => sub {
                          my ($self) = @_;
                         my $mech = WWW::Mechanize::Chrome->new(
                             %{ $self->mech_arguments },
                             );
                          $mech->allow( javascript => 1 );
                          return $mech;
                      }
    );

=head1 METHODS

=cut

sub _login {
    my ($self) = @_;

    my $mech = $self->_chrome_mech();
    $mech->get($self->_watched_uri);

    # Load login screen:
    $mech->wait_until_visible(
        selector => '#ap_email',
        timeout => 30
        );

    $mech->submit_form(with_fields => {email => $self->username });
    $mech->submit_form(with_fields => {password => $self->password });

    my $resp = $mech->response;
   
    if(!$resp->is_success) {
        die "Nope: ", $resp->status_line, "\n", $resp->content;
    }
    return 1;
}

=head2 get_watched

Call to retrieve watched episode data. If a L</per_show_callback> code
references has been provided, it will be called once for each show
found.

Returns a HashRef of shows, with the normalised show name as a key,
season numbers as values, each with an ArrayRef of episodes. Eg:

    { "Best Show" =>
      { 1 => [
        { num => 1, title => "First Episode" },
        { ... },
      ]},
    }

=cut

sub get_watched {
    my ($self) = @_;

    $self->_login();
    
    my %seen_show_uris;

    my %episodes = ();
    ## FIXME: Prefill with %episodes shows we've already finished
    ## watching? (or find some way we can skip reparsing them below)

    my $page_num = 1;
    my $mech = $self->_chrome_mech();
    while (1) {
        my $tree = HTML::TreeBuilder->new_from_content($mech->content);
        my @watched = $tree->look_down('id' => qr/^iyrListItemTitle/);

        foreach my $watch (@watched) {
            last if $page_num > $self->pages;
            
            my $a = $watch->look_down('_tag' => 'a');
            my $show_uri = URI->new_abs($a->attr('href'), $self->_watched_uri);
            
            $mech->get($show_uri);
            my $show_tree = HTML::TreeBuilder->new_from_content($mech->content);
            
            my $series_title = $show_tree->look_down(class => qr/\bdv-node-dp-title\b/)->as_text;
            my $release_year = $show_tree->look_down('data-automation-id' => 'release-year-badge')->as_text;

            my $season_sel_label_tag = $show_tree->look_down(_tag=>'label', for=>'av-droplist-av-atf-season-selector');
            my $season;
            # Counterexample:
            # https://www.amazon.co.uk/Episode-2/dp/B07HR1Q64L/ref=pd_ys_iyr31
            # has no drop-down, because it only has one season
            if (defined $season_sel_label_tag) {
                $season = $season_sel_label_tag->look_down(_tag => 'span')->as_text;
            } else {
                # This feels fragile, but I don't see a good way to do it,
                # so don't change the normal way of doing this (above),
                # but only add this as a fallback.
                $season = $show_tree->look_down(class => qr/\bdv-node-dp-title\b/)->right->as_text;
            }
            $season =~ s/^Season //;
            # say "series title: $series_title, season: '$season', release_year: $release_year";

            if ($season =~ m/^\(/) {
                # say "This seems to be a film, or we suck at finding the season.  Skipping";
                next;
            }

            my $norm = $self->normalise_names->($series_title);
            my $trakt_show_slug;
            if(%{ $self->already_seen } && $self->already_seen->{$norm}) {
                $trakt_show_slug = $self->already_seen()->{$norm}{show}{ids}{slug};
            } else {
                $trakt_show_slug = $self->_slugify_name($norm);
                $self->already_seen()->{$norm} = {
                    show => {ids => {slug => $trakt_show_slug } },
                    seasons => [],
                };
            }

            # if (not $trakt_show_slug) {
            #     for my $key (sort keys %{$self->already_seen}) {
            #         say "$key: " . $self->already_seen->{$key};
            #     }
            #     die "No series trakt id for '$series_title'";
            # } elsif ($trakt_show_slug eq '__SKIP__') {
            #     next;
            # }
            # We've already seen it?
            next if exists $episodes{$trakt_show_slug}{$season};

            for my $episode_elem ($show_tree->look_down(class => qr/\bjs-node-episode-container\b/)) {
                my $title_elem = $episode_elem->look_down(class => qr/\b(js-episode-title-name|dv-episode-noplayback-title)\b/);
                if (not $title_elem) {
                    # say "Odd, can't find title on $show_uri";
                    next;
                }
                my $title_text = $title_elem->as_text;
                my ($episode_number, $episode_title) = $title_text =~ m/^(\d+)\. (.*)$/;
                if (defined $episode_number) {
                    # say "Episode number: '$episode_number', episode_title: '$episode_title'";
                } else {
                    # say "Strange title: '$title_text'";
                }
                
                # Ah-ha!  Within the episode, there may be a span with role="progressbar".  The aria-valuenow attribute is episode completion percentage.
                # (If there is no role="progressbar", then it is unwatched.)
                my $progressbar = $episode_elem->look_down(role => 'progressbar');
                my $progress = 0;
                if ($progressbar) {
                    $progress = $progressbar->attr('aria-valuenow');
                }
                # say "Completion: ${progress}%";

                if (not defined $episode_number) {
                    warn "Skipping episode with no number for trakt";
                } elsif ($progress >= 90) {
                    push @{ $episodes{$trakt_show_slug}{$season} }, {
                        num => $episode_number,
                        title => $episode_title,
                    };
                }
            }
            $self->_run_callback($trakt_show_slug, $season, $episodes{$trakt_show_slug}{$season});
        }

        last unless my $next_img = $tree->look_down(id => 'iyrNext');
        my $next_uri = URI->new_abs($next_img->parent->attr('href'), $self->_watched_uri);
        $page_num++;
        last if $page_num >= $self->pages;
        if ($page_num >= 99e99) {
            warn "Terminating early for debugging";
            exit;
        }
        
        # say "Getting new amazon history page (#$page_num): $next_uri";
        $mech->get($next_uri);

    }

    return \%episodes;
}

sub _run_callback {
    my ($self, $slug, $season, $episodes) = @_;
    # No need to do anything at all, if we don't have any episodes to do anything with.
    # (on the other hand, how did we get here if so?)
    return if not $episodes or not @$episodes;
    
    ## Remove items from to_sync list that we have already seen:
    my ($seen_show) = grep { $_->{show}{ids}{slug} && $_->{show}{ids}{slug} eq $slug } (values %{$self->already_seen});
    my ($seen_season) = grep { $_->{number} == $season } (@{ $seen_show->{seasons} });
    foreach my $seen_ep (@{ $seen_season->{episodes} }) {
        $episodes = [ grep { $_->{num} != $seen_ep->{number}  } @$episodes ];
    }

    # print('Removed seen episodes: ', Dumper($episodes));
    ## We've seen them all
    return if !@$episodes;

    $self->per_show_callback->($slug, $season, $episodes);
    return;
    
}

sub _slugify_name {
    my ($self, $name) = @_;

    $name = lc($name);
    $name =~ s/\s+/-/;

    return $name;
}

=head1 SOURCE AVAILABILITY

This source is in Github:

	https://github.com/castaway/prime-watched/

=head1 AUTHOR

Jess Robinson, C<< <jrobinson@cpan.org> >>

=head1 COPYRIGHT AND LICENSE

Copyright © 2019-2020, Jess Robinson, <jrobinson@cpan.org>. All rights reserved.
You may redistribute this under the terms of the Artistic License 2.0.

=cut

1;
