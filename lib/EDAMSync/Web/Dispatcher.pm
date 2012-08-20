package EDAMSync::Web::Dispatcher;
use strict;
use warnings;
use utf8;

use Amon2::Web::Dispatcher::Lite;

use DateTime;
use DateTime::Format::MySQL;
use Data::UUID;


use EDAMSync::Web::C::Server;
use EDAMSync::Web::C::Client;
use EDAMSync::Web::C::Client::Api;

## TODO
## Amon2::Web::Dispatcher::RouterSimpleに乗り換える

get  '/'                       => sub { EDAMSync::Web::C::Client->index(@_) };
post '/create'                 => sub { EDAMSync::Web::C::Client->create(@_) };
get  '/entry/:entry_id'        => sub { EDAMSync::Web::C::Client->entry(@_) };
post '/entry/:entry_id'        => sub { EDAMSync::Web::C::Client->edit(@_) };
post '/entry/:entry_id/delete' => sub { EDAMSync::Web::C::Client->delete(@_) };

post  '/client/api/sync'       => sub { EDAMSync::Web::C::Client::Api->sync(@_) };

post '/server/api/sync'        => sub { EDAMSync::Web::C::Server->sync(@_) };
get  '/server/api/entries'     => sub { EDAMSync::Web::C::Server->entries(@_) };
get  '/server/api/state'       => sub { EDAMSync::Web::C::Server->state(@_) };

1;
