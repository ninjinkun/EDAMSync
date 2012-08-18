package EDAMSync::Web::Dispatcher;
use strict;
use warnings;
use utf8;

use Amon2::Web::Dispatcher::Lite;

use DateTime;
use DateTime::Format::MySQL;
use Data::UUID;

my $client_name = $ENV{EDAM_ENV} || 'client';
get '/' => sub {
    my ($c) = @_;
    my $entries = $c->dbh->selectall_arrayref(
        q{select * from entry ORDER BY usn},
        {
            Slice => {}},
    );

    my $client_status = $c->dbh->selectrow_hashref(
        q{SELECT * FROM client_status WHERE client_name = ?},
        {
        },
        $client_name,
    );

    $c->render('index.tt' => {
        client_name => $client_name,
        entries => $entries,
        client_status => $client_status,
    });
};

post '/create' => sub {
    my ($c) = @_;

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
};

get '/entry/:entry_id' => sub {
    my ($c, $args) = @_;
    my $entry_id = $args->{entry_id};
    
    my $entry = $c->dbh->selectrow_hashref(
        q{select * from entry where uuid = ?},
        {
        },
        $entry_id,
    );
    $c->render('entry.tt' => {
        client_name => $client_name,
        entry => $entry
    })
};

post '/entry/:entry_id' => sub {
    my ($c, $args) = @_;
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
};

post '/entry/:entry_id/delete' => sub {
    my ($c, $args) = @_;
    my $entry_id = $args->{entry_id};

    $c->dbh->do_i(
        q{DELETE FROM entry WHERE}, +{
            uuid => $entry_id,
        },
    );

    return $c->redirect('/'); 
};

use EDAMSync::Web::C::Server;
use EDAMSync::Web::C::Client;

any '/server/api/sync'    => sub { EDAMSync::Web::C::Server->sync(@_) };
get '/server/api/entries' => sub { EDAMSync::Web::C::Server->entries(@_) };
get '/server/api/state'   => sub { EDAMSync::Web::C::Server->state(@_) };

post '/client/api/sync'   => sub { EDAMSync::Web::C::Client->sync(@_) };


1;
