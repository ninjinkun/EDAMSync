package EDAMSync::Web::C::Client;
use strict;
use warnings;
use utf8;

use LWP::UserAgent;
use JSON::XS;
use SQL::Interp qw(sql_interp);;
use DateTime;
use DateTime::Format::MySQL;
use Data::UUID;
use MIME::Base64;

my $server_host = $ENV{SERVER_HOST} || 'localhost:5000';
my $client_name = $ENV{EDAM_ENV} || 'client';

sub sync {
    my ($class, $c) = @_;
    my $ua = LWP::UserAgent->new;

    my $uri = URI->new("http://$server_host/server/api/state");
    $uri->query_form(client => $client_name);
    my $res = $ua->get($uri);

    my $state = decode_json $res->content;

    my $full_sync_before = $state->{full_sync_before} ? DateTime->from_epoch(epoch => $state->{full_sync_before}) : undef;
    my $server_update_count = $state->{update_count};

    my $client_status = $c->dbh->selectrow_hashref(
        q{SELECT * FROM client_status WHERE client_name = ?},
        {
        },
        $client_name,
    );
    my $last_sync_time = $client_status->{last_sync_time} ? DateTime::Format::MySQL->parse_datetime($client_status->{last_sync_time}) : undef;
    my $last_update_count = $client_status->{last_update_count} || 0;

    warn $full_sync_before;
    warn $last_sync_time;
    if ((!defined $last_sync_time) ||  $full_sync_before > $last_sync_time) {
        ## full_sync
        my $will_sync_entries = $class->_sync($c);
        $class->_send_changes(
            $c,
            will_sync_entries => $will_sync_entries,
            last_update_count => $last_update_count,
            server_update_count => $server_update_count,
        );
        return $c->create_response(200, [], encode_json({
            synced_entries => $will_sync_entries,
             type => 'full sync',
        }));
        # return $c->render_json({
        #     synced_entries => $will_sync_entries,
        #     type => 'full sync',
        # });
    }
    elsif ($full_sync_before == $last_sync_time) {
        my $client_entries = $c->dbh->selectall_arrayref(
            q{SELECT * FROM entry WHERE dirty = 1},
            {
                Slice => {}},
        );
        $class->_send_changes(
            $c, 
            will_sync_entries => $client_entries,
            last_update_count => $last_update_count,
            server_update_count => $server_update_count,
        );
        warn $c->encoding;
        return $c->create_response(200, [], encode_json({
            synced_entries => $client_entries,
            type => 'send changes',
        }));
        # return $c->render_json({
        #     synced_entries => $client_entries,
        #     type => 'send changes',
        # });
    }
    else {
        warn 'Incremental Sync';
        ## incremental sync
        my $will_sync_entries = $class->_sync(
            $c,
            after_usn => $last_update_count,
        );
        $class->_send_changes(
            $c, 
            will_sync_entries => $will_sync_entries,
            last_update_count => $last_update_count,
            server_update_count => $server_update_count,

        );
        return $c->create_response(200, [], encode_json({
            synced_entries => $will_sync_entries,
            type => 'incrementl sync',
        }));

        # return $c->render_json({
        #     synced_entries => $will_sync_entries,
        #     type => 'incrementl sync',
        # });
    }
    
}
;
use XXX;
sub _sync {
    my ($class, $c, %args) = @_;
    my $after_usn = $args{after_usn};
    my $ua = LWP::UserAgent->new;

    my $uri = URI->new("http://$server_host/server/api/entries");
    $uri->query_form(after_usn => $after_usn) if $after_usn;
    ## full sync
    my $res = $ua->get($uri);
    my $json = decode_json $res->content;
    warn $after_usn;
    YYY my $server_entries = $json->{entries};
    my @server_uuids = map { $_->{uuid} } @$server_entries;
    my ($sql, @bind) = sql_interp(q{SELECT * FROM entry WHERE uuid IN}, \@server_uuids, q{or dirty = 1});
    my $client_entries = $c->dbh->selectall_arrayref(
        $sql,
        {
            Slice => {}},
        @bind,
    );

    my %server_uuids_map = map { $_->{uuid} => $_ } @$server_entries;
    my %client_uuids_map = map { $_->{uuid} => $_ } @$client_entries;

    my @will_save_entries = grep { !$client_uuids_map{$_->{uuid}} } @$server_entries;
    my @client_only_entries = grep { !$server_uuids_map{$_->{uuid}} } @$client_entries;
        
    my @will_sync_entries = grep { $_->{dirty} } @client_only_entries;
    my @will_remove_entries = grep { !$_->{dirty} } @client_only_entries;
        
    my @needs_resolve_entries = grep { $client_uuids_map{$_->{uuid}} } @$server_entries;
    for my $server_entry (@needs_resolve_entries) {
        my $client_entry = $client_uuids_map{$server_entry->{uuid}};
        if ($server_entry->{usn} == $client_entry->{usn}) {
            if ($client_entry->{dirty}) {
                ## overwrite
                push @will_sync_entries, $client_entry;
            } else {
                ## now syncing
            }
        } elsif ($server_entry->{usn} > $client_entry->{usn}) {
            push @will_save_entries, $server_entry;
        } else {
            ## conflict
            push @needs_resolve_entries, $client_entry;
        }
    }

    {
        my $txn = $c->dbh->txn_scope;
        for my $entry (@will_save_entries) {
            if ($client_uuids_map{$entry->{uuid}}) {
                $c->dbh->do_i(
                    q{UPDATE entry SET}, +{
                        body  => $entry->{body},
                        usn   => $entry->{usn},
                        dirty => 0,
                        updated_at => $entry->{updated_at},
                    },
                    q{WHERE}, +{
                        uuid => $entry->{uuid}
                    },
                );
            } else {
                warn "insert!!";
                $c->dbh->insert(entry => $entry);
            }
        }
        $txn->commit;
    }
    \@will_sync_entries;
}
use HTTP::Request::Common;
sub _send_changes {
    my ($class, $c, %args) = @_;
    my $will_sync_entries = $args{will_sync_entries};
    my $last_update_count = $args{last_update_count};
    my $server_update_count = $args{server_update_count};
    my $txn = $c->dbh->txn_scope;
    my $server_current_time;
    ## send changes
    {
        my $ua = LWP::UserAgent->new;

        my $res = $ua->post("http://$server_host/server/api/sync", [
            entries => JSON::XS->new->encode({entries => $will_sync_entries }),
            #            csrf_token => $c->get_csrf_defender_token,
        ]);
        my $json = decode_json($res->content);
        $server_current_time = DateTime->from_epoch(epoch => $json->{server_current_time});
        my $entries = $json->{entries};
        for my $entry (@$entries) {
            if ($entry->{usn} == $last_update_count + 1) {
                
            } elsif ($entry->{usn} > $last_update_count + 1) {
                
            }

            $c->dbh->do_i(
                q{UPDATE entry SET}, +{
                    usn   => $entry->{usn},
                    dirty => 0,
                },
                q{WHERE}, +{
                    uuid => $entry->{uuid}
                },
            );
            my $created_entry = $c->dbh->selectrow_hashref(
                q{select * from entry where uuid = ?},
                {
                },
                $entry->{uuid},
            );
        }
    
    }


    my $client_status = $c->dbh->selectrow_hashref(
        q{select * from client_status where client_name = ?},
        {
        },
        $client_name,
    );
    if ($client_status) {
        $c->dbh->do_i(
            q{UPDATE client_status SET},
            +{
                last_update_count =>  $server_update_count,
                last_sync_time    =>  DateTime::Format::MySQL->format_datetime($server_current_time),
            },
            q{where},
            +{
                client_name => $client_name
            }
        );
    } else {
        $c->dbh->insert(client_status => +{
            client_name => $client_name,
            last_update_count =>  $server_update_count,
            last_sync_time    =>  DateTime::Format::MySQL->format_datetime($server_current_time),
        });
    }
    $txn->commit;
}

1;
