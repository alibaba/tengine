package Test::Nginx::LWP;

use lib 'lib';
use lib 'inc';
use Test::Base -Base;

our $VERSION = '0.23';

our $NoLongString;

use LWP::UserAgent;
use Time::HiRes qw(sleep);
use Test::LongString;
use Test::Nginx::Util qw(
    setup_server_root
    write_config_file
    get_canon_version
    get_nginx_version
    trim
    show_all_chars
    parse_headers
    run_tests
    $ServerPortForClient
    $PidFile
    $ServRoot
    $ConfFile
    $ServerPort
    $RunTestHelper
    $NoNginxManager
    $RepeatEach
    worker_connections
    master_process_enabled
    master_on
    master_off
    config_preamble
    repeat_each
    no_shuffle
    no_root_location
);

our $UserAgent = LWP::UserAgent->new;
$UserAgent->agent(__PACKAGE__);
#$UserAgent->default_headers(HTTP::Headers->new);

#use Smart::Comments::JSON '##';

our @EXPORT = qw( plan run_tests run_test
    repeat_each config_preamble worker_connections
    master_process_enabled master_on master_off
    no_long_string no_shuffle no_root_location);

sub no_long_string () {
    $NoLongString = 1;
}

sub run_test_helper ($$);

$RunTestHelper = \&run_test_helper;

sub parse_request ($$) {
    my ($name, $rrequest) = @_;
    open my $in, '<', $rrequest;
    my $first = <$in>;
    if (!$first) {
        Test::More::BAIL_OUT("$name - Request line should be non-empty");
        die;
    }
    $first =~ s/^\s+|\s+$//g;
    my ($meth, $rel_url) = split /\s+/, $first, 2;
    my $url = "http://localhost:$ServerPortForClient" . $rel_url;

    my $content = do { local $/; <$in> };
    if ($content) {
        $content =~ s/^\s+|\s+$//s;
    }

    close $in;

    return {
        method  => $meth,
        url     => $url,
        content => $content,
    };
}

sub chunk_it ($$$) {
    my ($chunks, $start_delay, $middle_delay) = @_;
    my $i = 0;
    return sub {
        if ($i == 0) {
            if ($start_delay) {
                sleep($start_delay);
            }
        } elsif ($middle_delay) {
            sleep($middle_delay);
        }
        return $chunks->[$i++];
    }
}

sub run_test_helper ($$) {
    my ($block, $dry_run) = @_;

    my $request = $block->request;

    my $name = $block->name;

    #if (defined $TODO) {
    #$name .= "# $TODO";
    #}

    my $req_spec = parse_request($name, \$request);
    ## $req_spec
    my $method = $req_spec->{method};
    my $req = HTTP::Request->new($method);
    my $content = $req_spec->{content};

    if (defined ($block->request_headers)) {
        my $headers = parse_headers($block->request_headers);
        while (my ($key, $val) = each %$headers) {
            $req->header($key => $val);
        }
    }

    #$req->header('Accept', '*/*');
    $req->url($req_spec->{url});
    if ($content) {
        if ($method eq 'GET' or $method eq 'HEAD') {
            croak "HTTP 1.0/1.1 $method request should not have content: $content";
        }
        $req->content($content);
    } elsif ($method eq 'POST' or $method eq 'PUT') {
        my $chunks = $block->chunked_body;
        if (defined $chunks) {
            if (!ref $chunks or ref $chunks ne 'ARRAY') {

                Test::More::BAIL_OUT("$name - --- chunked_body should takes a Perl array ref as its value");
            }

            my $start_delay = $block->start_chunk_delay || 0;
            my $middle_delay = $block->middle_chunk_delay || 0;
            $req->content(chunk_it($chunks, $start_delay, $middle_delay));
            if (!defined $req->header('Content-Type')) {
                $req->header('Content-Type' => 'text/plain');
            }
        } else {
            if (!defined $req->header('Content-Type')) {
                $req->header('Content-Type' => 'text/plain');
            }

            $req->header('Content-Length' => 0);
        }
    }

    if ($block->more_headers) {
        my @headers = split /\n+/, $block->more_headers;
        for my $header (@headers) {
            next if $header =~ /^\s*\#/;
            my ($key, $val) = split /:\s*/, $header, 2;
            #warn "[$key, $val]\n";
            $req->header($key => $val);
        }
    }

    #warn "req: ", $req->as_string, "\n";
    #warn "DONE!!!!!!!!!!!!!!!!!!!!";

    my $res = HTTP::Response->new;
    unless ($dry_run) {
        $res = $UserAgent->request($req);
    }

    #warn "res returned!!!";

    if ($dry_run) {
        SKIP: {
            Test::More::skip("$name - tests skipped due to $dry_run", 1);
        }
    } else {
        if (defined $block->error_code) {
            is($res->code, $block->error_code, "$name - status code ok");
        } else {
            is($res->code, 200, "$name - status code ok");
        }
    }

    if (defined $block->response_headers) {
        my $headers = parse_headers($block->response_headers);
        while (my ($key, $val) = each %$headers) {
            my $expected_val = $res->header($key);
            if (!defined $expected_val) {
                $expected_val = '';
            }
            if ($dry_run) {
                SKIP: {
                    Test::More::skip("$name - tests skipped due to $dry_run", 1);
                }
            } else {
                is $expected_val, $val,
                    "$name - header $key ok";
            }
        }
    } elsif (defined $block->response_headers_like) {
        my $headers = parse_headers($block->response_headers_like);
        while (my ($key, $val) = each %$headers) {
            my $expected_val = $res->header($key);
            if (!defined $expected_val) {
                $expected_val = '';
            }
            if ($dry_run) {
                SKIP: {
                    Test::More::skip("$name - tests skipped due to $dry_run", 1);
                }
            } else {
                like $expected_val, qr/^$val$/,
                    "$name - header $key like ok";
            }
        }
    }

    if (defined $block->response_body) {
        my $content = $res->content;
        if (defined $content) {
            $content =~ s/^TE: deflate,gzip;q=0\.3\r\n//gms;
        }

        $content =~ s/^Connection: TE, close\r\n//gms;
        my $expected = $block->response_body;
        $expected =~ s/\$ServerPort\b/$ServerPort/g;
        $expected =~ s/\$ServerPortForClient\b/$ServerPortForClient/g;
        #warn show_all_chars($content);

        if ($dry_run) {
            SKIP: {
                Test::More::skip("$name - tests skipped due to $dry_run", 1);
            }
        } else {
            if ($NoLongString) {
                is($content, $expected, "$name - response_body - response is expected");
            } else {
                is_string($content, $expected, "$name - response_body - response is expected");
            }
            #is($content, $expected, "$name - response_body - response is expected");
        }

    } elsif (defined $block->response_body_like) {
        my $content = $res->content;
        if (defined $content) {
            $content =~ s/^TE: deflate,gzip;q=0\.3\r\n//gms;
        }
        $content =~ s/^Connection: TE, close\r\n//gms;
        my $expected_pat = $block->response_body_like;
        $expected_pat =~ s/\$ServerPort\b/$ServerPort/g;
        $expected_pat =~ s/\$ServerPortForClient\b/$ServerPortForClient/g;
        my $summary = trim($content);

        if ($dry_run) {
            SKIP: {
                Test::More::skip("$name - tests skipped due to $dry_run", 1);
            }
        } else {
            like($content, qr/$expected_pat/s, "$name - response_body_like - response is expected ($summary)");
        }
    }
}

1;
__END__

=encoding utf-8

=head1 NAME

Test::Nginx::LWP - LWP-backed test scaffold for the Nginx C modules

=head1 SYNOPSIS

    use Test::Nginx::LWP;

    plan tests => $Test::Nginx::LWP::RepeatEach * 2 * blocks();

    run_tests();

    __DATA__

    === TEST 1: sanity
    --- config
        location /echo {
            echo_before_body hello;
            echo world;
        }
    --- request
        GET /echo
    --- response_body
    hello
    world
    --- error_code: 200


    === TEST 2: set Server
    --- config
        location /foo {
            echo hi;
            more_set_headers 'Server: Foo';
        }
    --- request
        GET /foo
    --- response_headers
    Server: Foo
    --- response_body
    hi


    === TEST 3: clear Server
    --- config
        location /foo {
            echo hi;
            more_clear_headers 'Server: ';
        }
    --- request
        GET /foo
    --- response_headers_like
    Server: nginx.*
    --- response_body
    hi


    === TEST 4: set request header at client side and rewrite it
    --- config
        location /foo {
            more_set_input_headers 'X-Foo: howdy';
            echo $http_x_foo;
        }
    --- request
        GET /foo
    --- request_headers
    X-Foo: blah
    --- response_headers
    X-Foo:
    --- response_body
    howdy


    === TEST 3: rewrite content length
    --- config
        location /bar {
            more_set_input_headers 'Content-Length: 2048';
            echo_read_request_body;
            echo_request_body;
        }
    --- request eval
    "POST /bar\n" .
    "a" x 4096
    --- response_body eval
    "a" x 2048


    === TEST 4: timer without explicit reset
    --- config
        location /timer {
            echo_sleep 0.03;
            echo "elapsed $echo_timer_elapsed sec.";
        }
    --- request
        GET /timer
    --- response_body_like
    ^elapsed 0\.0(2[6-9]|3[0-6]) sec\.$


    === TEST 5: small buf (using 2-byte buf)
    --- config
        chunkin on;
        location /main {
            client_body_buffer_size    2;
            echo "body:";
            echo $echo_request_body;
            echo_request_body;
        }
    --- request
    POST /main
    --- start_chunk_delay: 0.01
    --- middle_chunk_delay: 0.01
    --- chunked_body eval
    ["hello", "world"]
    --- error_code: 200
    --- response_body eval
    "body:

    helloworld"

=head1 DESCRIPTION

This module provides a test scaffold based on L<LWP::UserAgent> for automated testing in Nginx C module development.

This class inherits from L<Test::Base>, thus bringing all its
declarative power to the Nginx C module testing practices.

You need to terminate or kill any Nginx processes before running the test suite if you have changed the Nginx server binary. Normally it's as simple as

  killall nginx
  PATH=/path/to/your/nginx-with-memc-module:$PATH prove -r t

This module will create a temporary server root under t/servroot/ of the current working directory and starts and uses the nginx executable in the PATH environment.

You will often want to look into F<t/servroot/logs/error.log>
when things go wrong ;)

=head1 Sections supported

The following sections are supported:

=over

=item config

=item http_config

=item request

=item request_headers

=item more_headers

=item response_body

=item response_body_like

=item response_headers

=item response_headers_like

=item error_code

=item chunked_body

=item middle_chunk_delay

=item start_chunk_delay

=back

=head1 Samples

You'll find live samples in the following Nginx 3rd-party modules:

=over

=item ngx_echo

L<http://wiki.nginx.org/NginxHttpEchoModule>

=item ngx_headers_more

L<http://wiki.nginx.org/NginxHttpHeadersMoreModule>

=item ngx_chunkin

L<http://wiki.nginx.org/NginxHttpChunkinModule>

=item ngx_memc

L<http://wiki.nginx.org/NginxHttpMemcModule>

=back

=head1 SOURCE REPOSITORY

This module has a Git repository on Github, which has access for all.

    http://github.com/agentzh/test-nginx

If you want a commit bit, feel free to drop me a line.

=head1 AUTHOR

agentzh (章亦春) C<< <agentzh@gmail.com> >>

=head1 COPYRIGHT & LICENSE

Copyright (c) 2009-2014, agentzh C<< <agentzh@gmail.com> >>.

This module is licensed under the terms of the BSD license.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

=over

=item *

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

=item *

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

=item *

Neither the name of the authors nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission. 

=back

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 

=head1 SEE ALSO

L<Test::Nginx::Socket>, L<Test::Base>.

