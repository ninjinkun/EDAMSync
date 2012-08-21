package EDAMSync::Web::C::Client::Api;
use strict;
use warnings;
use utf8;

use LWP::UserAgent;
use JSON;
use SQL::Interp qw(sql_interp);;
use DateTime;
use DateTime::Format::MySQL;
use Data::UUID;

my $server_host = EDAMSync->config->{server_host};

sub sync {
    my ($class, $c) = @_;
    my $ua = LWP::UserAgent->new;

    my $uri = URI->new("http://$server_host/server/api/state");
    $uri->query_form(client => $c->config->{client_name});
    my $res = $ua->get($uri);

    my $state = decode_json $res->content;

    my $full_sync_before = $state->{full_sync_before} ? DateTime->from_epoch(epoch => $state->{full_sync_before}) : undef;
    my $server_update_count = $state->{update_count};

    my $client_status = $c->dbh->selectrow_hashref(
        q{SELECT * FROM client_status WHERE client_name = ?},
        {
        },
        $c->config->{client_name},
    );
    my $last_sync_time = $client_status->{last_sync_time} ? DateTime::Format::MySQL->parse_datetime($client_status->{last_sync_time}) : undef;
    my $last_update_count = $client_status->{last_update_count} || 0;

    warn $full_sync_before . 'full sync before';
    warn $last_sync_time . 'last sync time';
    if ((!defined $last_sync_time) ||  $full_sync_before > $last_sync_time) {
        ## full_sync
        my %res = $class->_sync($c);
        my $will_sync_entries = $res{will_sync_entries};
        my $conflicted_entries = $res{conflicted_entries};

        my %send_change_res = $class->_send_changes(
            $c,
            will_sync_entries => $will_sync_entries,
            last_update_count => $last_update_count,
        );

        my $synchronized_entries = $send_change_res{synchronized_entries};
        my @conflicted_entries = (@$conflicted_entries, @{$send_change_res{conflicted_entries}});

        return $c->render_json({
            status               => scalar @conflicted_entries ? 'conflict' : 'ok',
            synchronized_entries => $synchronized_entries,
            conflicted_entries   => \@conflicted_entries,
            type                 => 'full sync',
        });
    }
    elsif (defined $full_sync_before && defined $last_sync_time && $full_sync_before == $last_sync_time) {
        my $client_entries = $c->dbh->selectall_arrayref(
            q{SELECT * FROM entry WHERE dirty = 1},
            {
                Slice => {}},
        );
        my%res = $class->_send_changes(
            $c, 
            will_sync_entries => $client_entries,
            last_update_count => $last_update_count,
        );
        my $synchronized_entries = $res{synchronized_entries};
        my $conflicted_entries = $res{conflicted_entries};
        return $c->render_json({
            status               => scalar @$conflicted_entries ? 'conflict' : 'ok',
            synchronized_entries => $synchronized_entries,
            conflicted_entries   => $conflicted_entries,
            type                 => 'send changes',
        });
    }
    else {
        warn 'Incremental Sync';
        ## incremental sync
        my %res = $class->_sync(
            $c,
            after_usn => $last_update_count,
        );
        my $will_sync_entries = $res{will_sync_entries};
        my $conflicted_entries = $res{conflicted_entries};

        my %send_res = $class->_send_changes(
            $c, 
            will_sync_entries => $will_sync_entries,
            last_update_count => $last_update_count,
        );
        my $synchronized_entries = $send_res{synchronized_entries};
        @$conflicted_entries = (@$conflicted_entries, @{$send_res{conflicted_entries}});
        return $c->render_json({
            status => scalar @$conflicted_entries ? 'conflict' : 'ok',
            synchronized_entries => $synchronized_entries,
            conflicted_entries => $conflicted_entries,
            type => 'incrementl sync',
        });
    }
    
}

sub _sync {
    my ($class, $c, %args) = @_;
    my $after_usn = $args{after_usn};
    my $ua = LWP::UserAgent->new;

    my $uri = URI->new("http://$server_host/server/api/entries");
    $uri->query_form(after_usn => $after_usn) if $after_usn;
    ## full sync
    my $res = $ua->get($uri);
    my $json = decode_json $res->content;
    warn 'after usn!! ' . $after_usn;
    my $server_entries = $json->{entries};
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
    my @conflicted_entries;

    for my $server_entry (@needs_resolve_entries) {
        my $client_entry = $client_uuids_map{$server_entry->{uuid}};
        if ($server_entry->{usn} == $client_entry->{usn}) {
            if ($client_entry->{dirty}) {
                ## overwrite
                push @will_sync_entries, $client_entry;
            } else {
                ## now syncing
            }
        }
        elsif ($server_entry->{usn} > $client_entry->{usn}) {
            if ($client_entry->{dirty})  {
                ## conflict
                push @conflicted_entries, +{
                    client_entries => $client_entry,
                    server_entries => $server_entries,
                };
            }
            else {
                push @will_save_entries, $server_entry;
            }
        }
    }

    {
        my $txn = $c->dbh->txn_scope;
        for my $entry (@will_save_entries) {
            if ($client_uuids_map{$entry->{uuid}}) {
                $c->dbh->do_i(
                    q{UPDATE entry SET} => +{
                        body  => $entry->{body},
                        usn   => $entry->{usn},
                        dirty => 0,
                        updated_at => $entry->{updated_at},
                    },
                    q{WHERE} => +{
                        uuid => $entry->{uuid}
                    },
                );
            } else {
                warn "insert!!";
                $c->dbh->insert(entry => $entry);
            }
        }
        for my $entry (@will_remove_entries) {
            $c->dbh->do_i(
                q{DELETE FROM entry WHERE} => {
                    uuid => $entry->{uuid},
                }
            );
        }
        $txn->commit;
    }
    (
        will_sync_entries  => \@will_sync_entries, 
        conflicted_entries => \@conflicted_entries,
    );
}

sub _send_changes {
    my ($class, $c, %args) = @_;
    my $will_sync_entries = $args{will_sync_entries};
    my $last_update_count = $args{last_update_count};


    ## send changes
    my $txn = $c->dbh->txn_scope;

    my $ua = LWP::UserAgent->new;

    my $res = $ua->post("http://$server_host/server/api/sync", [
        entries => JSON->new->encode({entries => $will_sync_entries }),
        #            csrf_token => $c->get_csrf_defender_token,
    ]);
#    return if $res->code != 200;

    my $json = decode_json($res->content || '{}');
    my $server_current_time = DateTime->from_epoch(epoch => $json->{server_current_time});
    my $server_update_count = $json->{server_update_count};
    my $server_entries = $json->{entries};

    my @conflicted_entries = @{$json->{conflicted_entries} || []};
    my @synchronized_entries;

    for my $server_entry (@$server_entries) {
        if ($server_entry->{usn} == $last_update_count + 1) {
            ## last_update_countを更新する

        } elsif ($server_entry->{usn} > $last_update_count + 1) {
            ## incremental syncを再実行する

        }

        $c->dbh->do_i(
            q{UPDATE entry SET}, +{
                usn   => $server_entry->{usn},
                dirty => 0,
            },
            q{WHERE}, +{
                uuid => $server_entry->{uuid}
            },
        );
        my $synchronized_entry = $c->dbh->selectrow_hashref(
            q{select * from entry where uuid = ?},
            {
            },
            $server_entry->{uuid},
        );
        push @synchronized_entries, $synchronized_entry;
    }
    $c->dbh->do_i(q{REPLACE INTO client_status}, +{
        client_name => $c->config->{client_name},
        last_update_count =>  $server_update_count,
        last_sync_time    =>  DateTime::Format::MySQL->format_datetime($server_current_time),
    });

    $txn->commit;

    (
        conflicted_entries => \@conflicted_entries,
        synchronized_entries    => \@synchronized_entries,
    );
}

## 今回は別のエントリーを作ることで対処する
sub resolve {
    my ($class, $c) = @_;
    my $json = JSON->new->decode($c->req->param('conflicted_entries') || '{}');
    my @conflicted_entries = @{$json->{conflicted_entries} || []};
    
    my $txn = $c->dbh->txn_scope;
    my @resolved_entries;
    my @uuids;
    for my $pair (@conflicted_entries) {
        my $client_entry = $pair->{client};
        my $new_uuid = Data::UUID->new->create_str;
        $c->dbh->insert(entry => +{ 
            uuid       => $new_uuid,
            body       => $client_entry->{body},
            usn        => 0,
            updated_at => DateTime::Format::MySQL->format_datetime(DateTime->now),
            created_at => DateTime::Format::MySQL->format_datetime(DateTime->now),
            dirty      => 1,
        });
        $c->dbh->do_i(q{DELETE from entry WHERE}, +{
            uuid => $client_entry->{uuid},
        });
        push @uuids, $new_uuid,
    }
    
    my ($sql, @bind) = sql_interp(q{SELECT * FROM entry WHERE uuid IN}, \@uuids);
    my $resolved_entries = $c->dbh->selectall_arrayref(
        $sql,
        {
            Slice => {}
        },
        @bind,
    );

    $txn->commit;
    $c->render_json({
        status => 'ok',
        resolved_entries => $resolved_entries,
    });
}

1;
