package EDAMSync::Web::C::Client;
use strict;
use warnings;
use utf8;

use SQL::Interp qw(sql_interp);;
use DateTime;
use DateTime::Format::MySQL;
use Data::UUID;

sub index {
    my ($class, $c) = @_;
    my $entries = $c->dbh->selectall_arrayref(
        q{select * from entry ORDER BY updated_at DESC},
        {
            Slice => {}
        },
    );

    my $client_status = $c->dbh->selectrow_hashref(
        q{SELECT * FROM client_status WHERE client_name = ?},
        {},
        $c->config->{client_name},
    );

    $c->render('index.tt' => {
        client_name => $c->config->{client_name},
        entries => $entries,
        client_status => $client_status,
    });
}

sub entry {
    my ($class, $c, $args) = @_;
    my $entry_id = $args->{entry_id};
    
    my $entry = $c->dbh->selectrow_hashref(
        q{select * from entry where uuid = ?},
        {
        },
        $entry_id,
    );
    $c->render('entry.tt' => {
        client_name => $c->config->{client_name},
        entry => $entry
    })
}

sub create {
    my ($class, $c) = @_;

    if (my $body = $c->req->param('body')) {
        my $update_count_row = $c->dbh->selectrow_hashref(
            q{SELECT max(usn) as update_count FROM entry},
            {
            },
        );
        my $update_count = $update_count_row->{update_count} || 0;

        $c->dbh->insert(entry => +{
            body       => $body,
            created_at => DateTime::Format::MySQL->format_datetime(DateTime->now),
            updated_at => DateTime::Format::MySQL->format_datetime(DateTime->now),
            uuid       => Data::UUID->new->create_str,
            dirty      => 1,
            usn        => 0,
        });
    }
    return $c->redirect('/'); 
}

sub edit {
    my ($class, $c, $args) = @_;
    my $entry_id = $args->{entry_id};

    if (my $body = $c->req->param('body')) {
        my $usn  = $c->req->param('usn');

        my $txn = $c->dbh->txn_scope;

        my $update_count_row = $c->dbh->selectrow_hashref(
            q{SELECT max(usn) as update_count FROM entry},
            {
            },
        );
        my $update_count = $update_count_row->{update_count} || 0;

        $c->dbh->do_i(
            q{UPDATE entry SET}, +{
                body       => $body,
                dirty      => 1,
                updated_at => DateTime::Format::MySQL->format_datetime(DateTime->now),
            },
            q{WHERE}, +{
                uuid => $entry_id,
            },
        );
        $txn->commit;
    }
    return $c->redirect('/entry/' . $entry_id); 
}

sub delete {
    my ($class, $c, $args) = @_;
    my $entry_id = $args->{entry_id};

    $c->dbh->do_i(
        q{DELETE FROM entry WHERE}, +{
            uuid => $entry_id,
        },
    );

    return $c->redirect('/'); 
}

1;
