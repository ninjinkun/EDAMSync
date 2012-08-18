package EDAMSync::Web::C::Server;
use strict;
use warnings;
use utf8;

use JSON::XS;
use DateTime;
use DateTime::Format::MySQL;
use SQL::Interp qw(sql_interp);;
use List::MoreUtils qw(all);
use Data::UUID;
use Encode;

sub state {
    my ($class, $c) = @_;

    my $client_name = 'client';

    my $full_sync_before_row = $c->dbh->selectrow_hashref(
        q{SELECT * FROM full_sync_before WHERE client_name = ?},
        {
        },
        $client_name,
    );
    
    my $update_count_row = $c->dbh->selectrow_hashref(
        q{SELECT max(usn) as update_count FROM entry},
        {
        },
    );
    my $full_sync_before_epoch = $full_sync_before_row->{full_sync_before} ? DateTime::Format::MySQL->parse_datetime($full_sync_before_row->{full_sync_before})->epoch : 0;
    $c->render_json({
        status           => 'ok',
        full_sync_before =>  $full_sync_before_epoch,
        update_count     => $update_count_row->{update_count}         || 0,
        current_time     => time(),
    });
};

sub entries {
    my ($class, $c) = @_;
    my $after_usn = $c->req->param('after_usn');
    my $entries;
    if (defined $after_usn) {
        $entries = $c->dbh->selectall_arrayref(
            q{SELECT * FROM entry WHERE usn > ?},
            {
                Slice => {}},
            $after_usn,
        );
    } else {
        $entries = $c->dbh->selectall_arrayref(
            q{select * from entry},
            {
                Slice => {}},
        );
    }

    $c->create_response(200, [], encode_json({
        status => 'ok',
        entries => $entries,
    }));
    # $c->render_json({
    #     status => 'ok',
    #     entries => $entries,
    # });
}


sub sync {
    my ($class, $c) = @_;
    my $client_name = $c->req->param('client_name');

    my $entries = JSON::XS->new->decode($c->req->param('entries'));

    $entries = $entries->{entries};
    my @created_entries;
    my @conflicted_entries;
    my @client_uuids = map { $_->{uuid} } @$entries;
    my $now = DateTime->now;

    my ($sql, @bind) = sql_interp(q{SELECT * FROM entry WHERE uuid IN}, \@client_uuids);
    my $server_entries = $c->dbh->selectall_arrayref(
        $sql,
        {
            Slice => {}},
        @bind,
    );
    my %server_entries_map = map { $_->{uuid} => $_ } @$server_entries;
    warn 'start';
    { 
        my $txn = $c->dbh->txn_scope;

        my $update_count_row = $c->dbh->selectrow_hashref(
            q{SELECT max(usn) as update_count FROM entry},
            {
            },
        );
        my $update_count = $update_count_row->{update_count};
        for my $client_entry (@$entries) {
            warn 'obj';
            all { defined $client_entry->{$_} }qw/body uuid usn/ or return $c->create_response(400, [], "parameter missing");


            my $server_entry = $server_entries_map{$client_entry->{uuid}};
            if ($server_entry) {
                ## update_entry
                if ($server_entry->{usn} == $client_entry->{usn} && $client_entry->{dirty}) {
                    my $update_count_row = $c->dbh->selectrow_hashref(
                        q{SELECT max(usn) as update_count FROM entry},
                        {
                        },
                    );
                    warn 'update db';
                    $c->dbh->do_i(
                        q{UPDATE entry SET}, +{
                            body => $client_entry->{body},
                            usn  => ++$update_count,
                            updated_at => DateTime::Format::MySQL->format_datetime(DateTime->now),
                        },
                        q{WHERE}, +{
                            uuid => $client_entry->{uuid},
                        },
                    );
                    my $updated_entry = $c->dbh->selectrow_hashref(
                        q{select * from entry where uuid = ?},
                        {
                        },
                        $client_entry->{uuid},
                    );
                    push @created_entries, $updated_entry;
                }
                else {
                    ## conflict
                    if ($server_entry->{body} ne $client_entry->{body}) {
                        push @conflicted_entries, $client_entry;
                    }
                }
            }
            else {

                warn 'Insert DB';
                $c->dbh->insert
                    (entry => +{
                    body       => $client_entry->{body},
                    created_at => DateTime::Format::MySQL->format_datetime(DateTime->now),
                    updated_at => DateTime::Format::MySQL->format_datetime(DateTime->now),
                    uuid       => $client_entry->{uuid},
                    usn        => ++$update_count,
                });
                my $created_entry = $c->dbh->selectrow_hashref(
                    q{select * from entry where uuid = ?},
                    {
                    },
                    $client_entry->{uuid},
                );
                push @created_entries, $created_entry;
            }
        }

        my $full_sync_before_row = $c->dbh->selectrow_hashref(
            q{select * from full_sync_before where client_name = ?},
            {
            },
            'client',
        );
        
        if ($full_sync_before_row) {
            $c->dbh->do_i(
                q{UPDATE full_sync_before SET}, +{
                    full_sync_before => DateTime::Format::MySQL->format_datetime($now),
                },
                q{WHERE}, +{
                    client_name => 'cleint',
                },
            );
        }
        else {
            $c->dbh->insert(full_sync_before => +{
                client_name      => 'client',
                full_sync_before => DateTime::Format::MySQL->format_datetime($now)
            });
        }

        $txn->commit;
    }
    $c->create_response(200, [], encode_json({
        status => @conflicted_entries ? 'ok' : 'conflicted',
        entries => \@created_entries || [],
        conflicted_entries => \@conflicted_entries || [],
        server_current_time => $now->epoch,
    }));
};

1;
