use strict;
use warnings;
use utf8;
use t::Util;
use Plack::Test;
use Plack::Util;
use Test::More;

my $app = Plack::Util::load_psgi 'app.psgi';
test_psgi
    app => $app,
    client => sub {
        my $cb = shift;
        for my $fname (qw(static/bootstrap/bootstrap.css robots.txt)) {
            my $req = HTTP::Request->new(GET => "http://localhost/$fname");
            my $res = $cb->($req);
            is($res->code, 200, $fname) or diag $res->content;
        }
    };

done_testing;
