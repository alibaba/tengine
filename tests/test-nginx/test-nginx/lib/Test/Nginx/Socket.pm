package Test::Nginx::Socket;

use lib 'lib';
use lib 'inc';

use Test::Base -Base;

our $VERSION = '0.23';

use POSIX qw( SIGQUIT SIGKILL SIGTERM SIGHUP );
use Encode;
#use Data::Dumper;
use Time::HiRes qw(sleep time);
use Test::LongString;
use List::MoreUtils qw( any );
use List::Util qw( sum );
use IO::Select ();
use File::Temp qw( tempfile );
use POSIX ":sys_wait_h";

use Test::Nginx::Util;

#use Smart::Comments::JSON '###';
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use POSIX qw(EAGAIN);
use IO::Socket;

#our ($PrevRequest, $PrevConfig);

our @EXPORT = qw( is_str plan run_tests run_test
  repeat_each config_preamble worker_connections
  master_process_enabled
  no_long_string workers master_on master_off
  log_level no_shuffle no_root_location
  server_name
  server_addr server_root html_dir server_port server_port_for_client
  timeout no_nginx_manager check_accum_error_log
  add_block_preprocessor bail_out add_cleanup_handler
  add_response_body_check
);

our $TotalConnectingTimeouts = 0;
our $PrevNginxPid;

sub send_request ($$$$@);

sub run_test_helper ($$);
sub test_stap ($$);

sub error_event_handler ($);
sub read_event_handler ($);
sub write_event_handler ($);
sub check_response_body ($$$$$$);
sub fmt_str ($);
sub gen_ab_cmd_from_req ($$@);
sub gen_curl_cmd_from_req ($$);
sub get_linear_regression_slope ($);
sub value_contains ($$);

$RunTestHelper = \&run_test_helper;
$CheckErrorLog = \&check_error_log;

sub set_http_config_filter ($) {
    $FilterHttpConfig = shift;
}

our @ResponseBodyChecks;

sub add_response_body_check ($) {
    push @ResponseBodyChecks, shift;
}

#  This will parse a "request"" string. The expected format is:
# - One line for the HTTP verb (POST, GET, etc.) plus optional relative URL
#   (default is /) plus optional HTTP version (default is HTTP/1.1).
# - More lines considered as the body of the request.
# Most people don't care about headers and this is enough.
#
#  This function will return a reference to a hash with the parsed elements
# plus information on the parsing itself like "how many white spaces were
# skipped before the VERB" (skipped_before_method), "was the version provided"
# (http_ver_size = 0).
sub parse_request ($$) {
    my ( $name, $rrequest ) = @_;
    open my $in, '<', $rrequest;
    my $first = <$in>;
    if ( !$first ) {
        bail_out("$name - Request line should be non-empty");
    }
    #$first =~ s/^\s+|\s+$//gs;
    my ($before_meth, $meth, $after_meth);
    my ($rel_url, $rel_url_size, $after_rel_url);
    my ($http_ver, $http_ver_size, $after_http_ver);
    my $end_line_size;
    if ($first =~ /^(\s*)(\S+)( *)((\S+)( *))?((\S+)( *))?(\s*)$/) {
        $before_meth = defined $1 ? length($1) : undef;
        $meth = $2;
        $after_meth = defined $3 ? length($3) : undef;
        $rel_url = $5;
        $rel_url_size = defined $5 ? length($5) : undef;
        $after_rel_url = defined $6 ? length($6) : undef;
        $http_ver = $8;
        if (!defined $8) {
            $http_ver_size = undef;
        } else {
            $http_ver_size = defined $8 ? length($8) : undef;
        }
        if (!defined $9) {
            $after_http_ver = undef;
        } else {
            $after_http_ver = defined $9 ? length($9) : undef;
        }
        $end_line_size = defined $10 ? length($10) : undef;
    } else {
        bail_out("$name - Request line is not valid. Should be 'meth [url [version]]' but got \"$first\".");
    }
    if ( !defined $rel_url ) {
        $rel_url = '/';
        $rel_url_size = 0;
        $after_rel_url = 0;
    }
    if ( !defined $http_ver ) {
        $http_ver = 'HTTP/1.1';
        $http_ver_size = 0;
        $after_http_ver = 0;
    }

    #my $url = "http://localhost:$ServerPortForClient" . $rel_url;

    my $content = do { local $/; <$in> };
    my $content_size;
    if ( !defined $content ) {
        $content = "";
        $content_size = 0;
    } else {
        $content_size = length($content);
    }

    #warn Dumper($content);

    close $in;

    return {
        method  => $meth,
        url     => $rel_url,
        content => $content,
        http_ver => $http_ver,
        skipped_before_method => $before_meth,
        method_size => length($meth),
        skipped_after_method => $after_meth,
        url_size => $rel_url_size,
        skipped_after_url => $after_rel_url,
        http_ver_size => $http_ver_size,
        skipped_after_http_ver => $after_http_ver + $end_line_size,
        content_size => $content_size,
    };
}

# From a parsed request, builds the "moves" to apply to the original request
# to transform it (e.g. add missing version). Elements of the returned array
# are of 2 types:
# - d : number of characters to remove.
# - s_* : number of characters (s_s) to replace by value (s_v).
sub get_moves($) {
    my ($parsed_req) = @_;
    return ({d => $parsed_req->{skipped_before_method}},
                          {s_s => $parsed_req->{method_size},
                           s_v => $parsed_req->{method}},
                          {d => $parsed_req->{skipped_after_method}},
                          {s_s => $parsed_req->{url_size},
                           s_v => $parsed_req->{url}},
                          {d => $parsed_req->{skipped_after_url}},
                          {s_s => $parsed_req->{http_ver_size},
                           s_v => $parsed_req->{http_ver}},
                          {d => $parsed_req->{skipped_after_http_ver}},
                          {s_s => 0,
                           s_v => $parsed_req->{headers}},
                          {s_s => $parsed_req->{content_size},
                           s_v => $parsed_req->{content}}
                         );
}

#  Apply moves (see above) to an array of packets that correspond to a request.
# The use of this function is explained in the build_request_from_packets
# function.
sub apply_moves($$) {
    my ($r_packet, $r_move) = @_;
    my $current_packet = shift @$r_packet;
    my $current_move = shift @$r_move;
    my $in_packet_cursor = 0;
    my @result = ();
    while (defined $current_packet) {
        if (!defined $current_move) {
            push @result, $current_packet;
            $current_packet = shift @$r_packet;
            $in_packet_cursor = 0;
        } elsif (defined $current_move->{d}) {
            # Remove stuff from packet
            if ($current_move->{d} > length($current_packet) - $in_packet_cursor) {
                # Eat up what is left of packet.
                $current_move->{d} -= length($current_packet) - $in_packet_cursor;
                if ($in_packet_cursor > 0) {
                    # Something in packet from previous iteration.
                    push @result, $current_packet;
                }
                $current_packet = shift @$r_packet;
                $in_packet_cursor = 0;
            } else {
                # Remove from current point in current packet
                substr($current_packet, $in_packet_cursor, $current_move->{d}) = '';
                $current_move = shift @$r_move;
            }
        } else {
            # Substitute stuff
            if ($current_move->{s_s} > length($current_packet) - $in_packet_cursor) {
                #   {s_s=>3, s_v=>GET} on ['GE', 'T /foo']
                $current_move->{s_s} -= length($current_packet) - $in_packet_cursor;
                substr($current_packet, $in_packet_cursor) = substr($current_move->{s_v}, 0, length($current_packet) - $in_packet_cursor);
                push @result, $current_packet;
                $current_move->{s_v} = substr($current_move->{s_v}, length($current_packet) - $in_packet_cursor);
                $current_packet = shift @$r_packet;
                $in_packet_cursor = 0;
            } else {
                substr($current_packet, $in_packet_cursor, $current_move->{s_s}) = $current_move->{s_v};
                $in_packet_cursor += length($current_move->{s_v});
                $current_move = shift @$r_move;
            }
        }
    }
    return \@result;
}
#  Given a request as an array of packets, will parse it, append the appropriate
# headers and return another array of packets.
#  The function implemented here can be high-level summarized as:
#   1 - Concatenate all packets to obtain a string representation of request.
#   2 - Parse the string representation
#   3 - Get the "moves" from the parsing
#   4 - Apply the "moves" to the packets.
sub build_request_from_packets($$$$$) {
    my ( $name, $more_headers, $is_chunked, $conn_header, $request_packets ) = @_;
    # Concatenate packets as a string
    my $parsable_request = '';
    my @packet_length;
    for my $one_packet (@$request_packets) {
        $parsable_request .= $one_packet;
        push @packet_length, length($one_packet);
    }
    #  Parse the string representation.
    my $parsed_req = parse_request( $name, \$parsable_request );

    # Append headers
    my $len_header = '';
    if (   !$is_chunked
        && defined $parsed_req->{content}
        && $parsed_req->{content} ne ''
        && $more_headers !~ /(?:^|\n)Content-Length:/ )
    {
        $parsed_req->{content} =~ s/^\s+|\s+$//gs;

        $len_header .=
          "Content-Length: " . length( $parsed_req->{content} ) . "\r\n";
    }

    $more_headers =~ s/(?<!\r)\n/\r\n/gs;

    my $headers = '';

    if ($more_headers !~ /(?:^|\n)Host:/msi) {
        $headers .= "Host: $ServerName\r\n";
    }

    if ($more_headers !~ /(?:^|\n)Connection/msi) {
        $headers .= "Connection: $conn_header\r\n";
    }

    $headers .= "$more_headers$len_header\r\n";

    $parsed_req->{method} .= ' ';
    $parsed_req->{url} .= ' ';
    $parsed_req->{http_ver} .= "\r\n";
    $parsed_req->{headers} = $headers;

    #  Get the moves from parsing
    my @elements_moves = get_moves($parsed_req);
    # Apply them to the packets.
    return apply_moves($request_packets, \@elements_moves);
}

sub parse_more_headers ($) {
    my ($in) = @_;
    my @headers = split /\n+/, $in;
    my $is_chunked;
    my $out = '';
    for my $header (@headers) {
        next if $header =~ /^\s*\#/;
        my ($key, $val) = split /:\s*/, $header, 2;
        if (lc($key) eq 'transfer-encoding' and $val eq 'chunked') {
            $is_chunked = 1;
        }

        #warn "[$key, $val]\n";
        $out .= "$key: $val\r\n";
    }
    return $out, $is_chunked;
}

#  Returns an array of array of hashes from the block. Each element of
# the first-level array is a request.
#  Each request is an array of the "packets" to be sent. Each packet is a
# string to send, with an (optionnal) delay before sending it.
#  This function parses (and therefore defines the syntax) of "request*"
# sections. See documentation for supported syntax.
sub get_req_from_block ($) {
    my ($block) = @_;
    my $name = $block->name;

    my @req_list = ();

    if (defined $block->raw_request) {

        # Should be deprecated.
        if (ref $block->raw_request && ref $block->raw_request eq 'ARRAY') {

            #  User already provided an array. So, he/she specified where the
            # data should be split. This allows for backward compatibility but
            # should use request with arrays as it provides the same functionnality.
            my @rr_list = ();
            for my $elt (@{ $block->raw_request }) {
                push @rr_list, {value => $elt};
            }
            push @req_list, \@rr_list;

        } else {
            push @req_list, [{value => $block->raw_request}];
        }

    } else {
        my $request;
        if (defined $block->request_eval) {

            diag "$name - request_eval DEPRECATED. Use request eval instead.";
            $request = eval $block->request_eval;
            if ($@) {
                warn $@;
            }

        } else {
            $request = $block->request;
            if (defined $request) {
                while ($request =~ s/^\s*\#[^\n]+\s+|^\s+//gs) {
                   # do nothing
                }
            }
            #warn "my req: $request";
        }

        my $more_headers = $block->more_headers || '';

        if ( $block->pipelined_requests ) {
            my $reqs = $block->pipelined_requests;
            if (!ref $reqs || ref $reqs ne 'ARRAY') {
                bail_out(
                    "$name - invalid entries in --- pipelined_requests");
            }
            my $i = 0;
            my $prq = "";
            for my $request (@$reqs) {
                my $conn_type;
                if ($i == @$reqs - 1) {
                    $conn_type = 'close';

                } else {
                    $conn_type = 'keep-alive';
                }

                my ($hdr, $is_chunked);
                if (ref $more_headers eq 'ARRAY') {
                    #warn "Found ", scalar @$more_headers, " entries in --- more_headers.";
                    $hdr = $more_headers->[$i];
                    if (!defined $hdr) {
                        bail_out("--- more_headers lacks data for the $i pipelined request");
                    }
                    ($hdr, $is_chunked) = parse_more_headers($hdr);
                    #warn "more headers: $hdr";

                } else {
                    ($hdr, $is_chunked)  = parse_more_headers($more_headers);
                }

                my $r_br = build_request_from_packets($name, $hdr,
                                      $is_chunked, $conn_type,
                                      [$request] );
                $prq .= $$r_br[0];
                $i++;
            }
            push @req_list, [{value =>$prq}];

        } else {
            my $is_chunked;
            if ($more_headers) {
                ($more_headers, $is_chunked) = parse_more_headers($more_headers);

            } else {
                $more_headers = '';
            }

            # request section.
            if (!ref $request) {
                # One request and it is a good old string.
                my $r_br = build_request_from_packets($name, $more_headers,
                                                      $is_chunked, 'close',
                                                      [$request] );
                push @req_list, [{value => $$r_br[0]}];
            } elsif (ref $request eq 'ARRAY') {
                # A bunch of requests...
                for my $one_req (@$request) {
                    if (!ref $one_req) {
                        # This request is a good old string.
                        my $r_br = build_request_from_packets($name, $more_headers,
                                                      $is_chunked, 'close',
                                                      [$one_req] );
                        push @req_list, [{value => $$r_br[0]}];
                    } elsif (ref $one_req eq 'ARRAY') {
                        # Request expressed as a serie of packets
                        my @packet_array = ();
                        for my $one_packet (@$one_req) {
                            if (!ref $one_packet) {
                                # Packet is a string.
                                push @packet_array, $one_packet;
                            } elsif (ref $one_packet eq 'HASH'){
                                # Packet is a hash with a value...
                                push @packet_array, $one_packet->{value};
                            } else {
                                bail_out "$name - Invalid syntax. $one_packet should be a string or hash with value.";
                            }
                        }
                        my $transformed_packet_array = build_request_from_packets($name, $more_headers,
                                                   $is_chunked, 'close',
                                                   \@packet_array);
                        my @transformed_req = ();
                        my $idx = 0;
                        for my $one_transformed_packet (@$transformed_packet_array) {
                            if (!ref $$one_req[$idx]) {
                                push @transformed_req, {value => $one_transformed_packet};
                            } else {
                                # Is a HASH (checked above as $one_packet)
                                $$one_req[$idx]->{value} = $one_transformed_packet;
                                push @transformed_req, $$one_req[$idx];
                            }
                            $idx++;
                        }
                        push @req_list, \@transformed_req;
                    } else {
                        bail_out "$name - Invalid syntax. $one_req should be a string or an array of packets.";
                    }
                }
            } else {
                bail_out(
                    "$name - invalid ---request : MUST be string or array of requests");
            }
        }

    }
    return \@req_list;
}

sub quote_sh_args ($) {
    my ($args) = @_;
    for my $arg (@$args) {
       if ($arg =~ m{^[- "&%;,|?*.+=\w:/()]*$}) {
          if ($arg =~ /[ "&%;,|?*()]/) {
             $arg = "'$arg'";
          }
          next;
       }
       $arg =~ s/\\/\\\\/g;
       $arg =~ s/'/\\'/g;
       $arg =~ s/\n/\\n/g;
       $arg =~ s/\r/\\r/g;
       $arg =~ s/\t/\\t/g;
       $arg = "\$'$arg'";
    }
    return "@$args";
}

sub run_test_helper ($$) {
    my ($block, $dry_run, $repeated_req_idx) = @_;

    #warn "repeated req idx: $repeated_req_idx";

    my $name = $block->name;

    my $r_req_list = get_req_from_block($block);

    if ( $#$r_req_list < 0 ) {
        bail_out("$name - request empty");
    }

    if (defined $block->curl) {
        my $req = $r_req_list->[0];
        my $cmd = gen_curl_cmd_from_req($block, $req);
        warn "# ", quote_sh_args($cmd), "\n";
    }

    if ($CheckLeak) {
        $dry_run = "the \"check leak\" testing mode";
    }

    if ($Benchmark) {
        $dry_run = "the \"benchmark\" testing mode";
    }

    if ($Benchmark && !defined $block->no_check_leak) {
        warn "$name\n";

        my $req = $r_req_list->[0];
        my ($nreqs, $concur);
        if ($Benchmark =~ /^\s*(\d+)(?:\s+(\d+))?\s*$/) {
            ($nreqs, $concur) = ($1, $2);
        }

        if ($BenchmarkWarmup) {
            my $cmd = gen_ab_cmd_from_req($block, $req, $BenchmarkWarmup, $concur);
            warn "Warming up with $BenchmarkWarmup requests...\n";
            system @$cmd;
        }

        my $cmd = gen_ab_cmd_from_req($block, $req, $nreqs, $concur);
        $cmd = quote_sh_args($cmd);

        warn "$cmd\n";
        system "unbuffer $cmd > /dev/stderr";
    }

    if ($CheckLeak && !defined $block->no_check_leak) {
        warn "$name\n";

        my $req = $r_req_list->[0];
        my $cmd = gen_ab_cmd_from_req($block, $req);

        # start a sub-process to run ab or weighttp
        my $pid = fork();
        if (!defined $pid) {
            bail_out("$name - fork() failed: $!");

        } elsif ($pid == 0) {
            # child process
            exec @$cmd;

        } else {
            # main process

            $Test::Nginx::Util::ChildPid = $pid;

            sleep(1);
            my $ngx_pid = get_pid_from_pidfile($name);
            if ($PrevNginxPid && $ngx_pid) {
                my $i = 0;
                while ($ngx_pid == $PrevNginxPid) {
                    sleep 0.01;
                    $ngx_pid = get_pid_from_pidfile($name);
                    if (++$i > 1000) {
                        bail_out("nginx cannot be started");
                    }
                }
            }
            $PrevNginxPid = $ngx_pid;
            my @rss_list;
            for (my $i = 0; $i < 100; $i++) {
                sleep 0.02;
                my $out = `ps -eo pid,rss|grep $ngx_pid`;
                if ($? != 0 && !is_running($ngx_pid)) {
                    if (is_running($pid)) {
                        kill(SIGKILL, $pid);
                        waitpid($pid, 0);
                    }

                    my $tb = Test::More->builder;
                    $tb->no_ending(1);

                    Test::More::fail("$name - the nginx process $ngx_pid is gone");
                    last;
                }

                my @lines = grep { $_->[0] eq $ngx_pid }
                                 map { s/^\s+|\s+$//g; [ split /\s+/, $_ ] }
                                 split /\n/, $out;

                if (@lines == 0) {
                    last;
                }

                if (@lines > 1) {
                    warn "Bad ps output: \"$out\"\n";
                    next;
                }

                my $ln = shift @lines;
                push @rss_list, $ln->[1];
            }

            #if ($Test::Nginx::Util::Verbose) {
            warn "LeakTest: [@rss_list]\n";
            #}

            if (@rss_list == 0) {
                warn "LeakTest: k=N/A\n";

            } else {
                my $k = get_linear_regression_slope(\@rss_list);
                warn "LeakTest: k=$k\n";
                #$k = get_linear_regression_slope([1 .. 100]);
                #warn "K = $k (1 expected)\n";
                #$k = get_linear_regression_slope([map { $_ * 2 } 1 .. 100]);
                #warn "K = $k (2 expected)\n";
            }

            if (is_running($pid)) {
                kill(SIGKILL, $pid);
                waitpid($pid, 0);
            }
        }
    }

    #warn "request: $req\n";

    my $timeout = parse_time($block->timeout);
    if ( !defined $timeout ) {
        $timeout = timeout();
    }

    my $res;
    my $req_idx = 0;
    my ($n, $need_array);

    for my $one_req (@$r_req_list) {
        my ($raw_resp, $head_req);

        if ($dry_run) {
            $raw_resp = "200 OK HTTP/1.0\r\nContent-Length: 0\r\n\r\n";

        } else {
            ($raw_resp, $head_req) = send_request( $one_req, $block->raw_request_middle_delay,
                $timeout, $block );
        }

        #warn "raw resonse: [$raw_resp]\n";

        if ($block->pipelined_requests) {
            $n = @{ $block->pipelined_requests };
            $need_array = 1;

        } else {
            $need_array = $#$r_req_list > 0;
        }

again:

        if ($Test::Nginx::Util::Verbose) {
            warn "!!! resp: [$raw_resp]";
        }

        if (!defined $raw_resp) {
            $raw_resp = '';
        }

        my ( $raw_headers, $left );

        if (!defined $block->ignore_response) {

            if ($Test::Nginx::Util::Verbose) {
                warn "parse response\n";
            }

            if (defined $block->http09) {
                $res = HTTP::Response->new(200, "OK", [], $raw_resp);
                $raw_headers = '';

            } else {
                ( $res, $raw_headers, $left ) = parse_response( $name, $raw_resp, $head_req );
            }
        }

        if (!$n) {
            if ($left) {
                my $name = $block->name;
                $left =~ s/([\0-\037\200-\377])/sprintf('\x{%02x}',ord $1)/eg;
                warn "WARNING: $name - unexpected extra bytes after last chunk in ",
                    "response: \"$left\"\n";
            }

        } else {
            $raw_resp = $left;
            $n--;
        }

        if (!defined $block->ignore_response) {
            check_error_code($block, $res, $dry_run, $req_idx, $need_array);
            check_raw_response_headers($block, $raw_headers, $dry_run, $req_idx, $need_array);
            check_response_headers($block, $res, $raw_headers, $dry_run, $req_idx, $need_array);
            check_response_body($block, $res, $dry_run, $req_idx, $repeated_req_idx, $need_array);
        }

        if ($n || $req_idx < @$r_req_list - 1) {
            if ($block->wait) {
                sleep($block->wait);
            }

            check_error_log($block, $res, $dry_run, $repeated_req_idx, $need_array);
        }

        $req_idx++;

        if ($n) {
            goto again;
        }
    }

    if ($block->wait) {
        sleep($block->wait);
    }

    if ($Test::Nginx::Util::Verbose) {
        warn "Testing stap...\n";
    }

    test_stap($block, $dry_run);

    check_error_log($block, $res, $dry_run, $repeated_req_idx, $need_array);
}


sub test_stap ($$) {
    my ($block, $dry_run) = @_;
    return if !$block->{stap};

    my $name = $block->name;

    my $reason;

    if ($dry_run) {
        $reason = "the lack of directive $dry_run";
    }

    if (!$UseStap) {
        $dry_run = 1;
        $reason ||= "env TEST_NGINX_USE_STAP is not set";
    }

    my $fname = stap_out_fname();

    if ($fname && ($fname eq '/dev/stdout' || $fname eq '/dev/stderr')) {
        $dry_run = 1;
        $reason ||= "TEST_NGINX_TAP_OUT is set to $fname";
    }

    my $stap_out = $block->stap_out;
    my $stap_out_like = $block->stap_out_like;
    my $stap_out_unlike = $block->stap_out_unlike;

    SKIP: {
        skip "$name - stap_out - tests skipped due to $reason", 1 if $dry_run;

        my $fh = stap_out_fh();
        if (!$fh) {
            bail_out("no stap output file handle found");
        }

        my $out = '';
        for (1..2) {
            if (sleep_time() < 0.2) {
                sleep 0.2;

            } else {
                sleep sleep_time();
            }

            while (<$fh>) {
                $out .= $_;
            }

            if ($out) {
                last;
            }
        }

        if ($Test::Nginx::Util::Verbose) {
            warn "stap out: $out\n";
        }

        if (defined $stap_out) {
            if ($NoLongString) {
                is($out, $block->stap_out, "$name - stap output expected");
            } else {
                is_string($out, $block->stap_out, "$name - stap output expected");
            }
        }

        if (defined $stap_out_like) {
            like($out || '', qr/$stap_out_like/sm,
                 "$name - stap output should match the pattern");
        }

        if (defined $stap_out_unlike) {
            unlike($out || '', qr/$stap_out_unlike/sm,
                   "$name - stap output should not match the pattern");
        }
    }
}


#  Helper function to retrieve a "check" (e.g. error_code) section. This also
# checks that tests with arrays of requests are arrays themselves.
sub get_indexed_value($$$$) {
    my ($name, $value, $req_idx, $need_array) = @_;
    if ($need_array) {
        if (ref $value && ref $value eq 'ARRAY') {
            return $$value[$req_idx];
        }

        bail_out("$name - You asked for many requests, the expected results should be arrays as well.");

    } else {
        # One element but still provided as an array.
        if (ref $value && ref $value eq 'ARRAY') {
            if ($req_idx != 0) {
                bail_out("$name - SHOULD NOT HAPPEN: idx != 0 and don't need array.");
            }

            return $$value[0];
        }

        return $value;
    }
}

sub check_error_code ($$$$$) {
    my ($block, $res, $dry_run, $req_idx, $need_array) = @_;

    my $name = $block->name;
    SKIP: {
        skip "$name - tests skipped due to $dry_run", 1 if $dry_run;

        if ( defined $block->error_code_like ) {

            my $val = get_indexed_value($name, $block->error_code_like, $req_idx, $need_array);
            like( ($res && $res->code) || '',
                qr/$val/sm,
                "$name - status code ok" );

        } elsif ( defined $block->error_code ) {
            is( ($res && $res->code) || '',
                get_indexed_value($name, $block->error_code, $req_idx, $need_array),
                "$name - status code ok" );

        } else {
            is( ($res && $res->code) || '', 200, "$name - status code ok" );
        }
    }
}

sub check_raw_response_headers($$$$$) {
    my ($block, $raw_headers, $dry_run, $req_idx, $need_array) = @_;
    my $name = $block->name;
    if (defined $block->raw_response_headers_like) {
        SKIP: {
            skip "$name - raw_response_headers_like - tests skipped due to $dry_run", 1 if $dry_run;
            my $expected = get_indexed_value($name,
                                             $block->raw_response_headers_like,
                                             $req_idx,
                                             $need_array);
            like $raw_headers, qr/$expected/s, "$name - raw resp headers like";
        }
    }

    if (defined $block->raw_response_headers_unlike) {
        SKIP: {
            skip "$name - raw_response_headers_unlike - tests skipped due to $dry_run", 1 if $dry_run;
            my $expected = get_indexed_value($name,
                                             $block->raw_response_headers_unlike,
                                             $req_idx,
                                             $need_array);
            unlike $raw_headers, qr/$expected/s, "$name - raw resp headers unlike";
        }
    }
}

sub check_response_headers($$$$$) {
    my ($block, $res, $raw_headers, $dry_run, $req_idx, $need_array) = @_;
    my $name = $block->name;
    if ( defined $block->response_headers ) {
        my $headers = parse_headers( get_indexed_value($name,
                                                       $block->response_headers,
                                                       $req_idx,
                                                       $need_array));
        while ( my ( $key, $val ) = each %$headers ) {
            if ( !defined $val ) {

                #warn "HIT";
                SKIP: {
                    skip "$name - response_headers - tests skipped due to $dry_run", 1 if $dry_run;
                    unlike $raw_headers, qr/^\s*\Q$key\E\s*:/ms,
                      "$name - header $key not present in the raw headers";
                }
                next;
            }

            $val =~ s/\$ServerPort\b/$ServerPort/g;
            $val =~ s/\$ServerPortForClient\b/$ServerPortForClient/g;

            my $actual_val = $res ? $res->header($key) : undef;
            if ( !defined $actual_val ) {
                $actual_val = '';
            }

            SKIP: {
                skip "$name - response_headers - tests skipped due to $dry_run", 1 if $dry_run;
                is $actual_val, $val, "$name - header $key ok";
            }
        }
    }
    elsif ( defined $block->response_headers_like ) {
        my $headers = parse_headers( get_indexed_value($name,
                                                       $block->response_headers_like,
                                                       $req_idx,
                                                       $need_array) );
        while ( my ( $key, $val ) = each %$headers ) {
            my $expected_val = $res->header($key);
            if ( !defined $expected_val ) {
                $expected_val = '';
            }
            SKIP: {
                skip "$name - response_headers_like - tests skipped due to $dry_run", 1 if $dry_run;
                like $expected_val, qr/^$val$/, "$name - header $key like ok";
            }
        }
    }
}

sub value_contains ($$) {
    my ($val, $pat) = @_;

    if (!ref $val || ref $val eq 'Regexp') {
        return $val =~ /\Q$pat\E/;
    }

    if (ref $val eq 'ARRAY') {
        for my $v (@$val) {
            if (value_contains($v, $pat)) {
                return 1;
            }
        }
    }

    return undef;
}

sub check_error_log ($$$$) {
    my ($block, $res, $dry_run, $repeated_req_idx, $need_array) = @_;
    my $name = $block->name;
    my $lines;

    my $check_alert_message = 1;
    my $check_crit_message = 1;
    my $check_emerg_message = 1;

    my $grep_pat;
    my $grep_pats = $block->grep_error_log;
    if (defined $grep_pats) {
        if (ref $grep_pats && ref $grep_pats eq 'ARRAY') {
            $grep_pat = $grep_pats->[$repeated_req_idx];

        } else {
            $grep_pat = $grep_pats;
        }
    }

    if (defined $grep_pat) {
        my $expected = $block->grep_error_log_out;
        if (!defined $expected) {
            bail_out("$name - No --- grep_error_log_out defined but --- grep_error_log is defined");
        }

        #warn "ref grep error log: ", ref $expected;

        if (ref $expected && ref $expected eq 'ARRAY') {
            #warn "grep error log out is an ARRAY";
            $expected = $expected->[$repeated_req_idx];
        }

        SKIP: {
            skip "$name - error_log - tests skipped due to $dry_run", 1 if $dry_run;

            $lines ||= error_log_data();

            my $matched_lines = '';
            for my $line (@$lines) {
                if (ref $grep_pat && $line =~ /$grep_pat/ || $line =~ /\Q$grep_pat\E/) {
                    my $matched = $&;
                    if ($matched !~ /\n/) {
                        $matched_lines .= $matched . "\n";
                    }
                }
            }

            if (ref $expected eq 'Regexp') {
                like($matched_lines, $expected, "$name - grep_error_log_out (req $repeated_req_idx)");

            } else {
                if ($NoLongString) {
                    is($matched_lines, $expected,
                       "$name - grep_error_log_out (req $repeated_req_idx)" );
                } else {
                    is_string($matched_lines, $expected,
                              "$name - grep_error_log_out (req $repeated_req_idx)");
                }
            }
        }
    }

    if (defined $block->error_log) {
        my $pats = $block->error_log;

        if (value_contains($pats, "[alert")) {
            undef $check_alert_message;
        }

        if (value_contains($pats, "[crit")) {
            undef $check_crit_message;
        }

        if (value_contains($pats, "[emerg")) {
            undef $check_emerg_message;
        }

        if (!ref $pats) {
            chomp $pats;
            my @lines = split /\n+/, $pats;
            $pats = \@lines;

        } elsif (ref $pats eq 'Regexp') {
            $pats = [$pats];

        } else {
            my @clone = @$pats;
            $pats = \@clone;
        }

        $lines ||= error_log_data();
        #warn "error log data: ", join "\n", @$lines;
        for my $line (@$lines) {
            for my $pat (@$pats) {
                next if !defined $pat;
                if (ref $pat && $line =~ /$pat/ || $line =~ /\Q$pat\E/) {
                    SKIP: {
                        skip "$name - error_log - tests skipped due to $dry_run", 1 if $dry_run;
                        pass("$name - pattern \"$pat\" matches a line in error.log (req $repeated_req_idx)");
                    }
                    undef $pat;
                }
            }
        }

        for my $pat (@$pats) {
            if (defined $pat) {
                SKIP: {
                    skip "$name - error_log - tests skipped due to $dry_run", 1 if $dry_run;
                    fail("$name - pattern \"$pat\" matches a line in error.log (req $repeated_req_idx)");
                    #die join("", @$lines);
                }
            }
        }
    }

    if (defined $block->no_error_log) {
        #warn "HERE";
        my $pats = $block->no_error_log;

        if (value_contains($pats, "[alert")) {
            undef $check_alert_message;
        }

        if (value_contains($pats, "[crit")) {
            undef $check_crit_message;
        }

        if (value_contains($pats, "[emerg")) {
            undef $check_emerg_message;
        }

        if (!ref $pats) {
            chomp $pats;
            my @lines = split /\n+/, $pats;
            $pats = \@lines;

        } elsif (ref $pats eq 'Regexp') {
            $pats = [$pats];

        } else {
            my @clone = @$pats;
            $pats = \@clone;
        }

        my %found;
        $lines ||= error_log_data();
        for my $line (@$lines) {
            for my $pat (@$pats) {
                next if !defined $pat;
                #warn "test $pat\n";
                if ((ref $pat && $line =~ /$pat/) || $line =~ /\Q$pat\E/) {
                    if ($found{$pat}) {
                        my $tb = Test::More->builder;
                        $tb->no_ending(1);

                    } else {
                        $found{$pat} = 1;
                    }

                    SKIP: {
                        skip "$name - no_error_log - tests skipped due to $dry_run", 1 if $dry_run;
                        my $ln = fmt_str($line);
                        my $p = fmt_str($pat);
                        fail("$name - pattern \"$p\" should not match any line in error.log but matches line \"$ln\" (req $repeated_req_idx)");
                    }
                }
            }
        }

        for my $pat (@$pats) {
            next if $found{$pat};
            if (defined $pat) {
                SKIP: {
                    skip "$name - no_error_log - tests skipped due to $dry_run", 1 if $dry_run;
                    my $p = fmt_str($pat);
                    pass("$name - pattern \"$p\" does not match a line in error.log (req $repeated_req_idx)");
                }
            }
        }
    }

    if ($check_alert_message && !$dry_run) {
        $lines ||= error_log_data();
        for my $line (@$lines) {
            #warn "test $pat\n";
            if ($line =~ /\[alert\]/) {
                my $ln = fmt_str($line);
                warn("WARNING: $name - $ln");
            }
        }
    }

    if ($check_crit_message && !$dry_run) {
        $lines ||= error_log_data();
        for my $line (@$lines) {
            #warn "test $pat\n";
            if ($line =~ /\[crit\]/) {
                my $ln = fmt_str($line);
                warn("WARNING: $name - $ln");
            }
        }
    }

    if ($check_emerg_message && !$dry_run) {
        $lines ||= error_log_data();
        for my $line (@$lines) {
            #warn "test $pat\n";
            if ($line =~ /\[emerg\]/) {
                my $ln = fmt_str($line);
                warn("WARNING: $name - $ln");
            }
        }
    }

    for my $line (@$lines) {
        #warn "test $pat\n";
        if ($line =~ /\bAssertion .*? failed\.$/) {
            my $tb = Test::More->builder;
            $tb->no_ending(1);

            chomp $line;
            fail("$name - $line");
        }
    }
}

sub fmt_str ($) {
    my $str = shift;
    chomp $str;
    $str =~ s/"/\\"/g;
    $str =~ s/\r/\\r/g;
    $str =~ s/\n/\\n/g;
    $str;
}

sub check_response_body ($$$$$$) {
    my ($block, $res, $dry_run, $req_idx, $repeated_req_idx, $need_array) = @_;
    my $name = $block->name;
    if (   defined $block->response_body
        || defined $block->response_body_eval )
    {
        my $content = $res ? $res->content : undef;
        if ( defined $content ) {
            $content =~ s/^TE: deflate,gzip;q=0\.3\r\n//gms;
            $content =~ s/^Connection: TE, close\r\n//gms;
        }

        my $expected;
        if ( $block->response_body_eval ) {
            diag "$name - response_body_eval is DEPRECATED. Use response_body eval instead.";
            $expected = eval get_indexed_value($name,
                                               $block->response_body_eval,
                                               $req_idx,
                                               $need_array);
            if ($@) {
                warn $@;
            }
        }
        else {
            $expected = get_indexed_value($name,
                                          $block->response_body,
                                          $req_idx,
                                          $need_array);
        }

        if ( $block->charset ) {
            Encode::from_to( $expected, 'UTF-8', $block->charset );
        }

        unless (ref $expected) {
            $expected =~ s/\$ServerPort\b/$ServerPort/g;
            $expected =~ s/\$ServerPortForClient\b/$ServerPortForClient/g;
        }

        #warn show_all_chars($content);

        #warn "no long string: $NoLongString";
        SKIP: {
            skip "$name - response_body - tests skipped due to $dry_run", 1 if $dry_run;
            if (ref $expected) {
                like $content, $expected, "$name - response_body - like (req $repeated_req_idx)";

            } else {
                if ($NoLongString) {
                    is( $content, $expected,
                        "$name - response_body - response is expected (req $repeated_req_idx)" );
                }
                else {
                    is_string( $content, $expected,
                        "$name - response_body - response is expected (req $repeated_req_idx)" );
                }
            }
        }

    } elsif (defined $block->response_body_like
             || defined $block->response_body_unlike)
    {
        my $patterns;
        my $type;
        my $cmp;
        if (defined $block->response_body_like) {
            $patterns = $block->response_body_like;
            $type = "like";
            $cmp = \&like;

        } else {
            $patterns = $block->response_body_unlike;
            $type = "unlike";
            $cmp = \&unlike;
        }

        my $content = $res ? $res->content : undef;
        if ( defined $content ) {
            $content =~ s/^TE: deflate,gzip;q=0\.3\r\n//gms;
            $content =~ s/^Connection: TE, close\r\n//gms;
        }
        my $expected_pat = get_indexed_value($name,
                                             $patterns,
                                             $req_idx,
                                             $need_array);
        $expected_pat =~ s/\$ServerPort\b/$ServerPort/g;
        $expected_pat =~ s/\$ServerPortForClient\b/$ServerPortForClient/g;
        my $summary = trim($content);
        if (!defined $summary) {
            $summary = "";
        }

        SKIP: {
            skip "$name - response_body_$type - tests skipped due to $dry_run", 1 if $dry_run;
            $cmp->( $content, qr/$expected_pat/s,
                "$name - response_body_$type - response is expected ($summary)"
            );
        }
    }

    for my $check (@ResponseBodyChecks) {
        $check->($block, $res->content, $req_idx, $repeated_req_idx, $dry_run);
    }
}

sub parse_response($$$) {
    my ( $name, $raw_resp, $head_req ) = @_;

    my $left;

    my $raw_headers = '';
    if ( $raw_resp =~ /(.*?\r\n)\r\n/s ) {

        #warn "\$1: $1";
        $raw_headers = $1;
    }

    #warn "raw headers: $raw_headers\n";

    my $res = HTTP::Response->parse($raw_resp);

    my $code = $res->code;

    my $enc = $res->header('Transfer-Encoding');
    my $len = $res->header('Content-Length');

    if ($code && $code !~ /^\d+$/) {
       undef $code;
       $res->code(undef);
    }

    if ($code && ($code == 304 || $code == 101)) {
        return $res, $raw_headers
    }

    if ( defined $enc && $enc eq 'chunked' ) {

        #warn "Found chunked!";
        my $raw = $res->content;
        if ( !defined $raw ) {
            $raw = '';
        }

        my $decoded = '';
        while (1) {
            if ( $raw =~ /\G 0 [\ \t]* \r\n \r\n /gcsx ) {
                if ( $raw =~ /\G (.+) /gcsx ) {
                    $left = $1;
                }

                last;
            }

            if ( $raw =~ m{ \G [\ \t]* ( [A-Fa-f0-9]+ ) [\ \t]* \r\n }gcsx ) {
                my $rest = hex($1);

                #warn "chunk size: $rest\n";
                my $bit_sz = 32765;
                while ( $rest > 0 ) {
                    my $bit = $rest < $bit_sz ? $rest : $bit_sz;

                    #warn "bit: $bit\n";
                    if ( $raw =~ /\G(.{$bit})/gcs ) {
                        $decoded .= $1;

                        #warn "decoded: [$1]\n";

                    } else {
                        my $tb = Test::More->builder;
                        $tb->no_ending(1);

                        fail("$name - invalid chunked data received "
                                ."(not enought octets for the data section)"
                        );
                        return;
                    }

                    $rest -= $bit;
                }

                if ( $raw !~ /\G\r\n/gcs ) {
                    my $tb = Test::More->builder;
                    $tb->no_ending(1);

                    fail(
                        "$name - invalid chunked data received (expected CRLF)."
                    );
                    return;
                }

            } elsif ( $raw =~ /\G.+/gcs ) {
                my $tb = Test::More->builder;
                $tb->no_ending(1);

                fail "$name - invalid chunked body received: $&";
                return;

            } else {
                my $tb = Test::More->builder;
                $tb->no_ending(1);

                fail "$name - no last chunk found - $raw";
                return;
            }
        }

        #warn "decoded: $decoded\n";
        $res->content($decoded);

    } elsif (defined $len && $len ne '' && $len >= 0) {
        my $raw = $res->content;
        if (length $raw < $len) {
            if (!$head_req) {
                warn "WARNING: $name - response body truncated: ",
                    "$len expected, but got ", length $raw, "\n";
            }

        } elsif (length $raw > $len) {
            my $content = substr $raw, 0, $len;
            $left = substr $raw, $len;
            $res->content($content);
            #warn "parsed body: [", $res->content, "]\n";
        }
    }

    return ( $res, $raw_headers, $left );
}

sub send_request ($$$$@) {
    my ( $req, $middle_delay, $timeout, $block, $tries ) = @_;

    my $name = $block->name;

    #warn "connecting...\n";

    my $sock = IO::Socket::INET->new(
        PeerAddr  => $ServerAddr,
        PeerPort  => $ServerPortForClient,
        Proto     => 'tcp',
        #ReuseAddr => 1,
        #ReusePort => 1,
        Blocking  => 0,
        Timeout   => $timeout,
    );

    if (!defined $sock) {
        $tries ||= 1;
        my $total_tries = $TotalConnectingTimeouts ? 20 : 50;
        if ($tries <= $total_tries) {
            my $wait = (sleep_time() + sleep_time() * $tries) * $tries / 2;
            if ($wait >= 1) {
                $wait = 1;
            }

            if (defined $Test::Nginx::Util::ChildPid) {
                my $errcode = $!;
                if (waitpid($Test::Nginx::Util::ChildPid, WNOHANG) == -1) {
                    warn "WARNING: Child process $Test::Nginx::Util::ChildPid is already gone.\n";
                    warn `tail -n20 $Test::Nginx::Util::ErrLogFile`;

                    my $tb = Test::More->builder;
                    $tb->no_ending(1);

                    fail("$name - Can't connect to $ServerAddr:$ServerPortForClient: $errcode (aborted)\n");
                    return;
                }
            }

            if ($wait >= 0.6) {
                warn "$name - Can't connect to $ServerAddr:$ServerPortForClient: $!\n";
                if ($tries + 1 <= $total_tries) {
                    warn "\tRetry connecting after $wait sec\n";
                }
            }

            sleep $wait;

            #warn "sending request";
            return send_request($req, $middle_delay, $timeout, $block, $tries + 1);

        }

        my $msg = "$name - Can't connect to $ServerAddr:$ServerPortForClient: $! (aborted)\n";
        if (++$TotalConnectingTimeouts < 3) {
            my $tb = Test::More->builder;
            $tb->no_ending(1);
            fail($msg);

        } else {
            bail_out($msg);
        }

        return;
    }

    #warn "connected";

    my @req_bits = ref $req ? @$req : ($req);

    my $head_req = 0;
    {
        my $req = join '', map { $_->{value} } @req_bits;
        #warn "Request: $req\n";
        if ($req =~ /^\s*HEAD\s+/) {
            #warn "Found HEAD request!\n";
            $head_req = 1;
        }
    }

    #my $flags = fcntl $sock, F_GETFL, 0
    #or die "Failed to get flags: $!\n";

    #fcntl $sock, F_SETFL, $flags | O_NONBLOCK
    #or die "Failed to set flags: $!\n";

    my $ctx = {
        resp         => '',
        write_offset => 0,
        buf_size     => 1024,
        req_bits     => \@req_bits,
        write_buf    => (shift @req_bits)->{"value"},
        middle_delay => $middle_delay,
        sock         => $sock,
        name         => $name,
        block        => $block,
    };

    my $readable_hdls = IO::Select->new($sock);
    my $writable_hdls = IO::Select->new($sock);
    my $err_hdls      = IO::Select->new($sock);

    while (1) {
        if (   $readable_hdls->count == 0
            && $writable_hdls->count == 0
            && $err_hdls->count == 0 )
        {
            last;
        }

        #warn "doing select...\n";

        my ($new_readable, $new_writable, $new_err) =
          IO::Select->select($readable_hdls, $writable_hdls, $err_hdls,
            $timeout);

        if (!defined $new_err
            && !defined $new_readable
            && !defined $new_writable)
        {

            # timed out
            timeout_event_handler($ctx);
            last;
        }

        for my $hdl (@$new_err) {
            next if !defined $hdl;

            error_event_handler($ctx);

            if ( $err_hdls->exists($hdl) ) {
                $err_hdls->remove($hdl);
            }

            if ( $readable_hdls->exists($hdl) ) {
                $readable_hdls->remove($hdl);
            }

            if ( $writable_hdls->exists($hdl) ) {
                $writable_hdls->remove($hdl);
            }

            for my $h (@$readable_hdls) {
                next if !defined $h;
                if ( $h eq $hdl ) {
                    undef $h;
                    last;
                }
            }

            for my $h (@$writable_hdls) {
                next if !defined $h;
                if ( $h eq $hdl ) {
                    undef $h;
                    last;
                }
            }

            close $hdl;
        }

        for my $hdl (@$new_readable) {
            next if !defined $hdl;

            my $res = read_event_handler($ctx);
            if ( !$res ) {

                # error occured
                if ( $err_hdls->exists($hdl) ) {
                    $err_hdls->remove($hdl);
                }

                if ( $readable_hdls->exists($hdl) ) {
                    $readable_hdls->remove($hdl);
                }

                if ( $writable_hdls->exists($hdl) ) {
                    $writable_hdls->remove($hdl);
                }

                for my $h (@$writable_hdls) {
                    next if !defined $h;
                    if ( $h eq $hdl ) {
                        undef $h;
                        last;
                    }
                }

                close $hdl;
            }
        }

        for my $hdl (@$new_writable) {
            next if !defined $hdl;

            my $res = write_event_handler($ctx);
            if ( !$res ) {

                # error occured
                if ( $err_hdls->exists($hdl) ) {
                    $err_hdls->remove($hdl);
                }

                if ( $readable_hdls->exists($hdl) ) {
                    $readable_hdls->remove($hdl);
                }

                if ( $writable_hdls->exists($hdl) ) {
                    $writable_hdls->remove($hdl);
                }

                close $hdl;

            } elsif ( $res == 2 ) {
                # all data has been written

                my $shutdown = $block->shutdown;
                if (defined $shutdown) {
                    if ($shutdown =~ /^$/s) {
                        $shutdown = 1;
                    }

                    #warn "shutting down with $shutdown";
                    shutdown($sock, $shutdown);
                }

                if ( $writable_hdls->exists($hdl) ) {
                    $writable_hdls->remove($hdl);
                }
            }
        }
    }

    return ($ctx->{resp}, $head_req);
}

sub timeout_event_handler ($) {
    my $ctx = shift;

    close($ctx->{sock});

    if (!defined $ctx->{block}->abort) {
        my $tb = Test::More->builder;
        $tb->no_ending(1);

        fail("ERROR: client socket timed out - $ctx->{name}\n");

    } else {
        sleep 0.005;
    }
}

sub error_event_handler ($) {
    warn "exception occurs on the socket: $!\n";
}

sub write_event_handler ($) {
    my ($ctx) = @_;

    while (1) {
        return undef if !defined $ctx->{write_buf};

        my $rest = length( $ctx->{write_buf} ) - $ctx->{write_offset};

  #warn "offset: $write_offset, rest: $rest, length ", length($write_buf), "\n";
  #die;

        if ( $rest > 0 ) {
            my $bytes;
            eval {
                $bytes = syswrite(
                    $ctx->{sock}, $ctx->{write_buf},
                    $rest,        $ctx->{write_offset}
                );
            };

            if ($@) {
                my $errmsg = "write failed: $@";
                warn "$errmsg\n";
                $ctx->{resp} =  $errmsg;
                return undef;
            }

            if ( !defined $bytes ) {
                if ( $! == EAGAIN ) {

                    #warn "write again...";
                    #sleep 0.002;
                    return 1;
                }
                my $errmsg = "write failed: $!";
                warn "$errmsg\n";
                if ( !$ctx->{resp} ) {
                    $ctx->{resp} = "$errmsg";
                }
                return undef;
            }

            #warn "wrote $bytes bytes.\n";
            $ctx->{write_offset} += $bytes;

        } else {
            # $rest == 0

            my $next_send = shift @{ $ctx->{req_bits} };

            if (!defined $next_send) {
                return 2;
            }

            $ctx->{write_buf} = $next_send->{'value'};
            $ctx->{write_offset} = 0;

            my $wait_time;

            if (!defined $next_send->{'delay_before'}) {
                if (defined $ctx->{middle_delay}) {
                    $wait_time = $ctx->{middle_delay};
                }

            } else {
                $wait_time = $next_send->{'delay_before'};
            }

            if ($wait_time) {
                #warn "sleeping..";
                sleep $wait_time;
            }
        }
    }

    # impossible to reach here...
    return undef;
}

sub read_event_handler ($) {
    my ($ctx) = @_;
    while (1) {
        my $read_buf;
        my $bytes = sysread( $ctx->{sock}, $read_buf, $ctx->{buf_size} );

        if ( !defined $bytes ) {
            if ( $! == EAGAIN ) {

                #warn "read again...";
                #sleep 0.002;
                return 1;
            }
            warn "WARNING: $ctx->{name} - HTTP response read failure: $!";
            return undef;
        }

        if ( $bytes == 0 ) {
            return undef;    # connection closed
        }

        $ctx->{resp} .= $read_buf;

        #warn "read $bytes ($read_buf) bytes.\n";
    }

    # impossible to reach here...
    return undef;
}

sub gen_curl_cmd_from_req ($$) {
    my ($block, $req) = @_;

    my $name = $block->name;

    $req = join '', map { $_->{value} } @$req;

    #use JSON::XS;
    #warn "Req: ",  JSON::XS->new->encode([$req]), "\n";

    my ($meth, $uri, $http_ver);
    if ($req =~ m{^\s*(\w+)\s+(\S+)\s+HTTP/(\S+)\r?\n}smig) {
        ($meth, $uri, $http_ver) = ($1, $2, $3);

    } elsif ($req =~ m{^\s*(\w+)\s+(.*\S)\r?\n}smig) {
        ($meth, $uri) = ($1, $2);
        $http_ver = '0.9';

    } else {
        bail_out "$name - cannot parse the status line in the request: $req";
    }

    my @args = ('curl', '-i');

    if ($meth eq 'HEAD') {
        push @args, '-I';

    } elsif ($meth ne 'GET') {
        warn "WARNING: --- curl: request method $meth not supported yet.\n";
    }

    if ($http_ver ne '1.1') {
        # HTTP 1.0 or HTTP 0.9
        push @args, '-0';
    }

    my @headers;
    if ($http_ver ge '1.0') {
        if ($req =~ m{\G(.*?)\r?\n\r?\n}gcs) {
            my $headers = $1;
            #warn "raw headers: $headers\n";
            @headers = grep {
                !/^Connection\s*:/i
                && !/^Host: \Q$ServerName\E$/i
                && !/^Content-Length\s*:/i
            } split /\r\n/, $headers;

        } else {
            bail_out "cannot parse the header entries in the request: $req";
        }
    }

    #warn "headers: @headers ", scalar(@headers), "\n";

    for my $h (@headers) {
        #warn "h: $h\n";
        if ($h =~ /^\s*User-Agent\s*:\s*(.*\S)/i) {
            push @args, '-A', $1;

        } else {
            push @args, '-H', $h;
        }
    }

    if ($req =~ m{\G.+}gcs) {
        warn "WARNING: --- curl: request body not supported.\n";
    }

    my $link;
    {
        my $server = $ServerAddr;
        my $port = $ServerPortForClient;
        $link = "http://$server:$port$uri";
    }

    push @args, $link;

    return \@args;
}

sub gen_ab_cmd_from_req ($$@) {
    my ($block, $req, $nreqs, $concur) = @_;

    $nreqs ||= 100000;
    $concur ||= 2;

    if ($nreqs < $concur) {
        $concur = $nreqs;
    }

    my $name = $block->name;

    $req = join '', map { $_->{value} } @$req;

    #use JSON::XS;
    #warn "Req: ",  JSON::XS->new->encode([$req]), "\n";

    my ($meth, $uri, $http_ver);
    if ($req =~ m{^\s*(\w+)\s+(\S+)\s+HTTP/(\S+)\r?\n}smig) {
        ($meth, $uri, $http_ver) = ($1, $2, $3);

    } elsif ($req =~ m{^\s*(\w+)\s+(.*\S)\r?\n}smig) {
        ($meth, $uri) = ($1, $2);
        $http_ver = '0.9';

    } else {
        bail_out "$name - cannot parse the status line in the request: $req";
    }

    #warn "HTTP version: $http_ver\n";

    my @opts = ("-c$concur", '-k', "-n$nreqs");

    my $prog;
    if ($http_ver eq '1.1' && $meth eq 'GET') {
        $prog = 'weighttp';

    } else {
        # HTTP 1.0 or HTTP 0.9
        $prog = 'ab';
        unshift @opts, '-r', '-d', '-S';
    }

    my @headers;
    if ($http_ver ge '1.0') {
        if ($req =~ m{\G(.*?)\r?\n\r?\n}gcs) {
            my $headers = $1;
            #warn "raw headers: $headers\n";
            @headers = grep {
                !/^Connection\s*:/i
                && !/^Host: \Q$ServerName\E$/i
                && !/^Content-Length\s*:/i
            } split /\r\n/, $headers;

        } else {
            bail_out "cannot parse the header entries in the request: $req";
        }
    }

    #warn "headers: @headers ", scalar(@headers), "\n";

    for my $h (@headers) {
        #warn "h: $h\n";
        if ($prog eq 'ab' && $h =~ /^\s*Content-Type\s*:\s*(.*\S)/i) {
            my $type = $1;
            push @opts, '-T', $type;

        } else {
            push @opts, '-H', $h;
        }
    }

    my $bodyfile;

    if ($req =~ m{\G.+}gcs || $meth eq 'POST' || $meth eq 'PUT') {
        my $body = $&;

        if (!defined $body) {
            $body = '';
        }

        my ($out, $bodyfile) = tempfile("bodyXXXXXXX", UNLINK => 1,
                                        SUFFIX => '.temp', TMPDIR => 1);
        print $out $body;
        close $out;

        if ($meth eq 'PUT') {
            push @opts, '-u', $bodyfile;

        } elsif ($meth eq 'POST') {
            push @opts, '-p', $bodyfile;

        } elsif ($meth eq 'GET') {
            warn "WARNING: method $meth not supported for ab when taking a request body\n";

        } else {
            warn "WARNING: method $meth not supported for ab when taking a request body\n";
            $meth = 'PUT';
            push @opts, '-p', $bodyfile;
        }
    }

    if ($meth eq 'HEAD') {
        unshift @opts, '-i';
    }

    my $link;
    {
        my $server = $ServerAddr;
        my $port = $ServerPortForClient;
        $link = "http://$server:$port$uri";
    }

    my @cmd = ($prog, @opts, $link);

    if ($Test::Nginx::Util::Verbose) {
        warn "command: @cmd\n";
    }

    return \@cmd;
}

sub get_linear_regression_slope ($) {
    my $list = shift;

    my $n = @$list;
    my $avg_x = ($n + 1) / 2;
    my $avg_y = sum(@$list) / $n;

    my $x = 0;
    my $avg_xy = sum(map { $x++; $x * $_ } @$list) / $n;
    my $avg_x2 = sum(map { $_ * $_ } 1 .. $n) / $n;
    my $denom = $avg_x2 - $avg_x * $avg_x;
    if ($denom == 0) {
        return 'Inf';
    }
    my $k = ($avg_xy - $avg_x * $avg_y) / $denom;
    return sprintf("%.01f", $k);
}

1;
__END__

=encoding utf-8

=head1 NAME

Test::Nginx::Socket - Socket-backed test scaffold for the Nginx C modules

=head1 SYNOPSIS

    use Test::Nginx::Socket;

    repeat_each(2);
    plan tests => repeat_each() * 3 * blocks();

    no_shuffle();
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


    === TEST 3: chunk size too small
    --- config
        chunkin on;
        location /main {
            echo_request_body;
        }
    --- more_headers
    Transfer-Encoding: chunked
    --- request eval
    "POST /main
    4\r
    hello\r
    0\r
    \r
    "
    --- error_code: 400
    --- response_body_like: 400 Bad Request

=head1 DESCRIPTION

This module provides a test scaffold based on non-blocking L<IO::Socket> for automated testing in Nginx C module development.

This class inherits from L<Test::Base>, thus bringing all its
declarative power to the Nginx C module testing practices.

You need to terminate or kill any Nginx processes before running the test suite if you have changed the Nginx server binary. Normally it's as simple as

  killall nginx
  PATH=/path/to/your/nginx-with-memc-module:$PATH prove -r t

This module will create a temporary server root under t/servroot/ of the current working directory and starts and uses the nginx executable in the PATH environment.

You will often want to look into F<t/servroot/logs/error.log>
when things go wrong ;)

=head1 Exported Perl Functions

The following Perl functions are exported by default:

=head2 run_tests

This is the main entry point of the test scaffold. Calling this Perl function before C<__DATA__> makes all the tests run.
Other configuration Perl functions I<must> be called before calling this C<run_tests> function.

=head2 no_shuffle

By default, the test scaffold always shuffles the order of the test blocks automatically. Calling this function before
calling C<run_tests> will disable the shuffling.

=head2 no_long_string

By default, failed string equality test will use the L<Test::LongString> module to generate the error message. Calling this function
before calling C<run_tests> will turn this off.

=head2 no_diff

When the C<no_long_string> function is called, the C<Text::Diff> module will be used to generate a diff for failed string equality test. Calling this C<no_diff> function before calling C<run_tests> will turn this diff output format off and just generate the raw "got" text and "expected" text.

=head2 worker_connections

Call this function before calling C<run_tests> to set the Nginx's C<worker_connections> configuration value. For example,

    worker_connections(1024);
    run_tests();

Default to 64.

=head2 repeat_each

Call this function with an integer argument before C<run_tests()> to ask the test scaffold
to run the specified number of duplicate requests for each test block. When it is called without argument, it returns the current setting.

Default to 1.

=head2 workers

Call this function before C<run_tests()> to configure Nginx's C<worker_processes> directive's value. For example,

    workers(2);

Default to 1.

=head2 master_on

Call this function before C<run_tests()> to turn on the Nginx master process.

By default, the master process is not enabled unless in the "HUP reload" testing mode.

=head2 log_level

Call this function before C<run_tests()> to set the default error log filtering level in Nginx.

This global setting can be overridden by the per-test-block C<--- log_level> sections.

Default to C<debug>.

=head2 check_accum_error_log

Make C<--- error_log> and C<--- no_error_log> check accumulated error log across duplicate requests controlled by C<repeat_each>. By default, only the error logs belonging to the individual C<repeat_each> request is tested.

=head2 no_root_location

By default, the Nginx configuration file generated by the test scaffold
automatically emits a C<location />. Calling this function before C<run_tests()>
disables this behavior such that the test blocks can have their own root locations.

=head2 bail_out

Aborting the whole test session (not just the current test file) with a specified message.

This function will also do all the necessary cleanup work. So always use this function instead of calling C<Test::More::BAIL_OUT()> directly.

For example,

    bail_out("something bad happened!");

=head2 add_cleanup_handler

Rigister custom cleanup handler for the current perl/prove process by specifying a Perl subroutine object as the argument.

For example,

    add_cleanup_handler(sub {
        kill INT => $my_own_child_pid;
        $my_own_socket->close()
    });

=head2 add_block_preprocessor

Add a custom Perl preprocessor to each test block by specifying a Perl subroutine object as the argument.

The processor subroutine is always run right before processing the test block.

This mechanism can be used to add custom sections or modify existing ones.

For example,

    add_block_preprocessor(sub {
        my $block = shift;

        # use "--- req_headers" for "--- more_Headers":
        $block->set_value("more_headers", $block->req_headers);

        # initialize external dependencies like memcached services...
    });

=head2 add_response_body_check

Add custom checks for testing response bodies by specifying a Perl subroutine object as the argument.

Below is an example for doing HTML title checks:

    add_response_body_check(sub {
            my ($block, $body, $req_idx, $repeated_req_idx, $dry_run) = @_;

            my $name = $block->name;
            my $expected_title = $block->resp_title;

            if ($expected_title && !ref $expected_title) {
                $expected_title =~ s/^\s*|\s*$//gs;
            }

            if (defined $expected_title) {
                SKIP: {
                    skip "$name - resp_title - tests skipped due to $dry_run", 1 if $dry_run;

                    my $title;
                    if ($body =~ m{<\s*title\s*>\s*(.*?)<\s*/\s*title\s*>}) {
                        $title = $1;
                        $title =~ s/\s*$//s;
                    }

                    is_str($title, $expected_title,
                           "$name - resp_title (req $repeated_req_idx)" );
                }
            }
        });

=head2 is_str

Performs intelligent string comparison subtests which honors both C<no_long_string> and regular expression references in the "expected" argument.

=head1 Sections supported

The following sections are supported:

=head2 config

Content of this section will be included in the "server" part of the generated
config file. This is the place where you want to put the "location" directive
enabling the module you want to test. Example:

        location /echo {
            echo_before_body hello;
            echo world;
        }

Sometimes you simply don't want to bother copying ten times the same
configuration for the ten tests you want to run against your module. One way
to do this is to write a config section only for the first test in your C<.t>
file. All subsequent tests will re-use the same config. Please note that this
depends on the order of test, so you should run C<prove> with variable
C<TEST_NGINX_NO_SHUFFLE=1> (see below for more on this variable).

Please note that config section goes through environment variable expansion
provided the variables to expand start with TEST_NGINX.
So, the following is a perfectly legal (provided C<TEST_NGINX_HTML_DIR> is
set correctly):

    location /main {
        echo_subrequest POST /sub -f $TEST_NGINX_HTML_DIR/blah.txt;
    }

=head2 http_config

Content of this section will be included in the "http" part of the generated
config file. This is the place where you want to put the "upstream" directive
you might want to test. Example:

    upstream database {
        postgres_server     127.0.0.1:$TEST_NGINX_POSTGRESQL_PORT
                            dbname=ngx_test user=ngx_test
                            password=wrong_pass;
    }

As you guessed from the example above, this section goes through environment
variable expansion (variables have to start with TEST_NGINX).

=head2 main_config

Content of this section will be included in the "main" part (or toplevel) of the generated
config file. This is very rarely used, except if you are testing nginx core
itself. Everything in C<--- main_config> will be put before the C<http {}> block generated automatically by the test scaffold.

This section goes through environment
variable expansion (variables have to start with TEST_NGINX).

=head2 post_main_config

Similar to C<main_config>, but the content will be put I<after> the C<http {}>
block generated by this module.

=head2 server_name

Specify a custom server name (via the "server_name" nginx config directive) for the
current test block. Default to "localhost".

=head2 init

Run a piece of Perl code specified as the content of this C<--- init> section before running the tests for the blocks. Note that it is only run once before *all* the repeated requests for this test block.

=head2 request

This is probably the most important section. It defines the request(s) you
are going to send to the nginx server. It offers a pretty powerful grammar
which we are going to walk through one example at a time.

In its most basic form, this section looks like that:

    --- request
    GET

This will just do a GET request on the root (i.e. /) of the server using
HTTP/1.1.

Of course, you might want to test something else than the root of your
web server and even use a different version of HTTP. This is possible:

    --- request
    GET /foo HTTP/1.0

Please note that specifying HTTP/1.0 will not prevent Test::Nginx from
sending the C<Host> header. Actually Test::Nginx always sends 2 headers:
C<Host> (with value localhost) and C<Connection> (with value C<close> for
simple requests and keep-alive for all but the last pipelined_requests).

You can also add a content to your request:

    --- request
    POST /foo
    Hello world

Test::Nginx will automatically calculate the content length and add the
corresponding header for you.

This being said, as soon as you want to POST real data, you will be interested
in using the more_headers section and using the power of Test::Base filters
to urlencode the content you are sending. Which gives us a
slightly more realistic example:

    --- more_headers
    Content-type: application/x-www-form-urlencoded
    --- request eval
    use URI::Escape;
    "POST /rrd/foo
    value=".uri_escape("N:12345")

Sometimes a test is more than one request. Typically you want to POST some
data and make sure the data has been taken into account with a GET. You can
do it using arrays:

    --- request eval
    ["POST /users
    name=foo", "GET /users/foo"]

This way, REST-like interfaces are pretty easy to test.

When you develop nifty nginx modules you will eventually want to test things
with buffers and "weird" network conditions. This is where you split
your request into network packets:

    --- request eval
    [["POST /users\nna", "me=foo"]]

Here, Test::Nginx will first send the request line, the headers it
automatically added for you and the first two letters of the body ("na" in
our example) in ONE network packet. Then, it will send the next packet (here
it's "me=foo"). When we talk about packets here, this is not exactly correct
as there is no way to guarantee the behavior of the TCP/IP stack. What
Test::Nginx can guarantee is that this will result in two calls to
C<syswrite>.

A good way to make I<almost> sure the two calls result in two packets is to
introduce a delay (let's say 2 seconds)before sending the second packet:

    --- request eval
    [["POST /users\nna", {value => "me=foo", delay_before => 2}]]

Of course, everything can be combined till your brain starts boiling ;) :

    --- request eval
    use URI::Escape;
    my $val="value=".uri_escape("N:12346");
    [["POST /rrd/foo
    ".substr($val, 0, 6),
    {value => substr($val, 6, 5), delay_before=>5},
    substr($val, 11)],  "GET /rrd/foo"]

Adding comments before the actual request spec is also supported, for example,

   --- request
   # this request contains the URI args
   # "foo" and "bar":
   GET /api?foo=1&bar=2

=head2 request_eval

Use of this section is deprecated and tests using it should replace it with
a C<request> section with an C<eval> filter. More explicitly:

    --- request_eval
    "POST /echo_body
    hello\x00\x01\x02
    world\x03\x04\xff"

should be replaced by:

    --- request eval
    "POST /echo_body
    hello\x00\x01\x02
    world\x03\x04\xff"

=head2 pipelined_requests

Specify pipelined requests that use a single keep-alive connection to the server.

Here is an example from ngx_lua's test suite:

    === TEST 7: discard body
    --- config
        location = /foo {
            content_by_lua '
                ngx.req.discard_body()
                ngx.say("body: ", ngx.var.request_body)
            ';
        }
        location = /bar {
            content_by_lua '
                ngx.req.read_body()
                ngx.say("body: ", ngx.var.request_body)
            ';
        }
    --- pipelined_requests eval
    ["POST /foo
    hello, world",
    "POST /bar
    hiya, world"]
    --- response_body eval
    ["body: nil\n",
    "body: hiya, world\n"]

=head2 more_headers

Adds the content of this section as headers to the request being sent. Example:

    --- more_headers
    X-Foo: blah

This will add C<X-Foo: blah> to the request (on top of the automatically
generated headers like C<Host>, C<Connection> and potentially
C<Content-Length>).

=head2 curl

When this section is specified, the test scaffold will try generating a C<curl> command line for the (first) test request.

For example,

    --- request
    GET /foo/bar?baz=3

    --- more_headers
    X-Foo: 3
    User-Agent: openresty

    --- curl

will produce the following line (to C<stderr>) while running this test block:

    # curl -i -H 'X-Foo: 3' -A openresty 'http://127.0.0.1:1984/foo/bar?baz=3'

You need to remember to set the C<TEST_NGINX_NO_CLEAN> environment to 1 to prevent the nginx
and other processes from quitting automatically upon test exits.

=head2 response_body

The expected value for the body of the submitted request.

    --- response_body
    hello

If the test is made of multiple requests, then the response_body B<MUST>
be an array and each request B<MUST> return the corresponding expected
body:

    --- request eval
    ["GET /hello", "GET /world"]
    --- response_body eval
    ["hello", "world"]

=head2 response_body_eval

Use of this section is deprecated and tests using it should replace it
with a C<request> section with an C<eval> filter. Therefore:

    --- response_body_eval
    "hello\x00\x01\x02
    world\x03\x04\xff"

should be replaced by:

    --- response_body eval
    "hello\x00\x01\x02
    world\x03\x04\xff"

=head2 response_body_like

The body returned by the request MUST match the pattern provided by this
section. Example:

    --- response_body_like
    ^elapsed 0\.00[0-5] sec\.$

If the test is made of multiple requests, then response_body_like B<MUST>
be an array and each request B<MUST> match the corresponding pattern.

=head2 response_body_unlike

Just like C<response_body_like> but this test only pass when the specified pattern
does I<not> match the actual response body data.

=head2 response_headers

The headers specified in this section are in the response sent by nginx.

    --- response_headers
    Content-Type: application/x-resty-dbd-stream

Of course, you can specify many headers in this section:

    --- response_headers
    X-Resty-DBD-Module:
    Content-Type: application/x-resty-dbd-stream

The test will be successful only if all headers are found in the response with
the appropriate values.

If the test is made of multiple requests, then response_headers B<MUST>
be an array and each element of the array is checked against the
response to the corresponding request.

=head2 response_headers_like

The value of the headers returned by nginx match the patterns.

    --- response_headers_like
    X-Resty-DBD-Module: ngx_drizzle \d+\.\d+\.\d+
    Content-Type: application/x-resty-dbd-stream

This will check that the response's C<Content-Type> is
application/x-resty-dbd-stream and that the C<X-Resty-DBD-Module> matches
C<ngx_drizzle \d+\.\d+\.\d+>.

The test will be successful only if all headers are found in the response and
if the values match the patterns.

If the test is made of multiple requests, then response_headers_like B<MUST>
be an array and each element of the array is checked against the
response to the corresponding request.

=head2 raw_response_headers_like

Checks the headers part of the response against this pattern. This is
particularly useful when you want to write tests of redirect functions
that are not bound to the value of the port your nginx server (under
test) is listening to:

    --- raw_response_headers_like: Location: http://localhost(?::\d+)?/foo\r\n

As usual, if the test is made of multiple requests, then
raw_response_headers_like B<MUST> be an array.

=head2 raw_response_headers_unlike

Just like C<raw_response_headers_like> but the subtest only passes when
the regex does I<not> match the raw response headers string.

=head2 error_code

The expected value of the HTTP response code. If not set, this is assumed
to be 200. But you can expect other things such as a redirect:

    --- error_code: 302

If the test is made of multiple requests, then
error_code B<MUST> be an array with the expected value for the response status
of each request in the test.

=head2 error_code_like

Just like C<error_code>, but accepts a Perl regex as the value, for example:

    --- error_code_like: ^(?:500)?$

If the test is made of multiple requests, then
error_code_like B<MUST> be an array with the expected value for the response status
of each request in the test.

=head2 timeout

Specify the timeout value (in seconds) for the HTTP client embedded into the test scaffold. This has nothing
to do with the server side configuration. When the timeout expires, the test scaffold will immediately
close the socket for connecting to the Nginx server being tested.

Note that, just as almost all the timeout settings in the Nginx world, this timeout
also specifies the maximum waiting time between two successive I/O events on the same socket handle,
rather than the total waiting time for the current socket operation.

When the timeout setting expires, a test failure will be
triggered with the message "ERROR: client socket timed out - TEST NAME", unless you have specified
C<--- abort> at the same time.

Here is an example:

    === TEST 1: test timeout
    --- location
        location = /t {
            echo_sleep 1;
            echo ok;
        }
    --- request
        GET /t
    --- response_body
    ok
    --- timeout: 1.5

An optional time unit can be specified, for example,

    --- timeout: 50ms

Acceptable time units are C<s> (seconds) and C<ms> (milliseconds). If no time unit is specified, then default to seconds.

=head2 error_log_file

Specify the global error log file for the current test block only.

Right now, it will not affect the C<--- error_log> section and etc accordingly.

=head2 error_log

Checks if the pattern or multiple patterns all appear in lines of the F<error.log> file.

For example,

    === TEST 1: matched with j
    --- config
        location /re {
            content_by_lua '
                m = ngx.re.match("hello, 1234", "([0-9]+)", "j")
                if m then
                    ngx.say(m[0])
                else
                    ngx.say("not matched!")
                end
            ';
        }
    --- request
        GET /re
    --- response_body
    1234
    --- error_log: pcre JIT compiling result: 1

Then the substring "pcre JIT compiling result: 1" must appear literally in a line of F<error.log>.

Multiple patterns are also supported, for example:

    --- error_log eval
    ["abc", qr/blah/]

then the substring "abc" must appear literally in a line of F<error.log>, and the regex C<qr/blah>
must also match a line in F<error.log>.

By default, only the part of the error logs corresponding to the current request is checked. You can make it check accumulated error logs by calling the C<check_accum_error_log> Perl function before calling C<run_tests> in the boilerplate Perl code above the C<__DATA__> line.

=head2 abort

Makes the test scaffold not to treat C<--- timeout> expiration as a test failure.

=head2 shutdown

Perform a C<shutdown>() operation on the client socket connecting to Nginx as soon as sending out
all the request data. This section takes an (optional) integer value for the argument to the
C<shutdown> function call. For example,

    --- shutdown: 1

will make the connection stop sending data, which is the default.

=head2 no_error_log

Very much like the C<--- error_log> section, but does the opposite test, i.e.,
pass only when the specified patterns of lines do not appear in the F<error.log> file at all.

Here is an example:

    --- no_error_log
    [error]

This test will fail when any of the line in the F<error.log> file contains the string C<"[error]">.

Just like the C<--- error_log> section, one can also specify multiple patterns:

    --- no_error_log eval
    ["abc", qr/blah/]

Then if any line in F<error.log> contains the string C<"abc"> or match the Perl regex C<qr/blah/>, then the test will fail.

=head2 grep_error_log

This section specifies the Perl regex pattern for filtering out the Nginx error logs.

You can specify a verbatim substring being matched in the error log messages, as in

    --- grep_error_log chop
    some thing we want to see

or specify a Perl regex object to match against the error log message lines, as in

    --- grep_error_log eval
    qr/something should be: \d+/

All the matched substrings in the error log messages will be concatenated by a newline character as a whole to be compared with the value of the C<--- grep_error_log_out> section.

=head2 grep_error_log_out

This section contains the expected output for the filtering operations specified by the C<--- grep_error_log> section.

If the filtered output varies among the repeated requests (specified by the C<repeat_each> function, then you can specify a Perl array as the value, as in

    --- grep_error_log_out eval
    ["output for req 0", "output for req 1"]

=head2 log_level

Overrides the default error log level for the current test block.

For example:

    --- log_level: debug

The default error log level can be specified in the Perl code by calling the C<log_level()> function, as in

    use Test::Nginx::Socket;

    repeat_each(2);
    plan tests => repeat_each() * (3 * blocks());

    log_level('warn');

    run_tests();

    __DATA__
    ...

=head2 raw_request

The exact request to send to nginx. This is useful when you want to test
some behaviors that are not available with "request" such as an erroneous
C<Content-Length> header or splitting packets right in the middle of headers:

    --- raw_request eval
    ["POST /rrd/taratata HTTP/1.1\r
    Host: localhost\r
    Connection: close\r
    Content-Type: application/",
    "x-www-form-urlencoded\r
    Content-Length:15\r\n\r\nvalue=N%3A12345"]

This can also be useful to tests "invalid" request lines:

    --- raw_request
    GET /foo HTTP/2.0 THE_FUTURE_IS_NOW

=head2 http09

Specifies that the HTTP 0.9 protocol is used. This affects how C<Test::Nginx::Socket>
parses the response.

Below is an example from ngx_headers_more module's test suite:

    === TEST 38: HTTP 0.9 (set)
    --- config
        location /foo {
            more_set_input_headers 'X-Foo: howdy';
            echo "x-foo: $http_x_foo";
        }
    --- raw_request eval
    "GET /foo\r\n"
    --- response_headers
    ! X-Foo
    --- response_body
    x-foo: 
    --- http09

=head2 ignore_response

Do not attempt to parse the response or run the response related subtests.

=head2 user_files

With this section you can create a file that will be copied in the
html directory of the nginx server under test. For example:

    --- user_files
    >>> blah.txt
    Hello, world

will create a file named C<blah.txt> in the html directory of the nginx
server tested. The file will contain the text "Hello, world".

Multiple files are supported, for example,

    --- user_files
    >>> foo.txt
    Hello, world!
    >>> bar.txt
    Hello, heaven!

An optional last modified timestamp (in elpased seconds since Epoch) is supported, for example,

    --- user_files
    >>> blah.txt 199801171935.33
    Hello, world

It's also possible to specify a Perl data structure for the user files
to be created, for example,

    --- user_files eval
    [
        [ "foo.txt" => "Hello, world!", 199801171935.33 ],
        [ "bar.txt" => "Hello, heaven!" ],
    ]

=head2 skip_eval

Skip the specified number of subtests (in the current test block) if the result of running a piece of Perl code is true.

The format for this section is

    --- skip_eval
    <subtest-count>: <perl-code>

For example, to skip 3 subtests when the current operating system is not Linux:

    --- skip_eval
    3: $^O ne 'linux'

or equivalently,

    --- skip_eval: 3: $^O ne 'linux'

=head2 skip_nginx

Skip the specified number of subtests (in the current test block)
for the specified version range of nginx.

The format for this section is

    --- skip_nginx
    <subtest-count>: <op> <version>

The <subtest-count> value must be a positive integer.
The <op> value could be either C<< > >>, C<< >= >>, C<< < >>, or C<< <= >>. the <version> part is a valid nginx version number, like C<1.0.2>.

An example is

    === TEST 1: sample
    --- config
        location /t { echo hello; }
    --- request
        GET /t
    --- response_body
    --- skip_nginx
    2: < 0.8.54

That is, skipping 2 subtests in this test block for nginx versions older than 0.8.54.

This C<skip_nginx> section only allows you to specify one boolean expression as
the skip condition. If you want to use two boolean expressions, you should use the C<skip_nginx2> section instead.

=head2 skip_nginx2

This section is similar to C<skip_nginx>, but the skip condition consists of two boolean expressions joined by the operator C<and> or C<or>.

The format for this section is

    --- skip_nginx2
    <subtest-count>: <op> <version> and|or <op> <version>

For example:

    === TEST 1: sample
    --- config
        location /t { echo hello; }
    --- request
        GET /t
    --- response_body
    --- skip_nginx2
    2: < 0.8.53 and >= 0.8.41

=head2 stap

This section is used to specify user systemtap script file (.stp file)

Here's an example:

    === TEST 1: stap sample
    --- config
        location /t { echo hello; }
    --- stap
    probe process("nginx").function("ngx_http_finalize_request")
    {
        printf("finalize %s?%s\n", ngx_http_req_uri($r),
               ngx_http_req_args($r))
    }
    --- stap_out
    finalize /test?a=3&b=4
    --- request
    GET /test?a=3&b=4
    --- response_body
    hello

There's some macros that can be used in the "--- stap" section value. These macros
will be expanded by the test scaffold automatically.

=over

=item C<F(function_name)>

This expands to C<probe process("nginx").function("function_name")>. For example,
 the sample above can be rewritten as

    === TEST 1: stap sample
    --- config
        location /t { echo hello; }
    --- stap
    F(ngx_http_finalize_request)
    {
        printf("finalize %s?%s\n", ngx_http_req_uri($r),
               ngx_http_req_args($r))
    }
    --- stap_out
    finalize /test?a=3&b=4
    --- request
    GET /test?a=3&b=4
    --- response_body
    hello

=item C<T()>

This macro will be expanded to C<println("Fire ", pp())>.

=item C<M(static-probe-name)>

This macro will be expanded to C<probe process("nginx").mark("static-probe-name")>.

For example,

    M(http-subrequest-start)
    {
        ...
    }

will be expanded to

    probe process("nginx").mark("http-subrequest-start")
    {
        ...
    }

=back

=head2 stap_out

This section specifies the expected literal output of the systemtap script specified by C<stap>.

=head2 stap_out_like

Just like C<stap_out>, but specify a Perl regex pattern instead.

=head2 stap_out_unlike

Just like C<stap_like>, but the subtest only passes when the specified pattern does I<not> match the output of the systemtap script.

=head2 wait

Takes an integer value for the seconds of time to wait right after processing the Nginx response and
before performing the error log and/or systemtap output checks.

=head2 udp_listen

Instantiates a UDP server listening on the port specified in the background for the test
case to access. The server will be started and shut down at each iteration of the test case
(if repeat_each is set to 3, then there are 3 iterations).

The UDP server will first read and discard a datagram and then send back a datagram with the content
specified by the C<udp_reply> section value.

Here is an example:

    === TEST 1: udp access
    --- config
        location = /t {
            content_by_lua '
                local udp = ngx.socket.udp()
                udp:setpeername("127.0.0.1", 19232)
                udp:send("blah")
                local data, err = udp:receive()
                ngx.say("received: ", data)
            ';
        }
    --- udp_listen: 19232
    --- udp_reply: hello world
    --- request
    GET /t
    --- response_body
    received: hello world

Datagram UNIX domain socket is also supported if a path name ending with ".sock" is given to this directive. For instance,

    === TEST 2: datagram unix domain socket access
    --- config
        location = /t {
            content_by_lua '
                local udp = ngx.socket.udp()
                udp:setpeername("unix:a.sock")
                udp:send("blah")
                local data, err = udp:receive()
                ngx.say("received: ", data)
            ';
        }
    --- udp_listen: a.sock
    --- udp_reply: hello world
    --- request
    GET /t
    --- response_body
    received: hello world

=head2 udp_reply

This section specifies the datagram reply content for the UDP server created by the C<udp_listen> section.

You can also specify a delay time before sending out the reply via the C<udp_reply_delay> section. By default, there is no delay.

An array value can be specified to make the embedded UDP server to send multiple replies as specified, for example:

    --- udp_reply eval
    [ "hello", "world" ]

This section also accepts a Perl subroutine value that can be used to
generate dynamic response packet or packets based on the actualactual query, for example:

    --- udp_reply eval
    sub {
        my $req = shift;
        return "hello, $req";
    }

The custom Perl subroutine can also return an array reference, for example,

    --- udp_reply eval
    sub {
        my $req = shift;
        return ["hello, $req", "hiya, $req"];
    }

See the C<udp_listen> section for more details.

=head2 udp_reply_delay

This section specifies the delay time before sending out the reply specified by the C<udp_reply> section.

It is C<0> delay by default.

An optional time unit can be specified, for example,

    --- udp_reply_delay: 50ms

Acceptable time units are C<s> (seconds) and C<ms> (milliseconds). If no time unit is specified, then default to seconds.

=head2 udp_query

Tests whether the UDP query sent to the embedded UDP server is equal to what is specified by this directive.

For example,

    === TEST 1: udp access
    --- config
        location = /t {
            content_by_lua '
                local udp = ngx.socket.udp()
                udp:setpeername("127.0.0.1", 19232)
                udp:send("blah")
                local data, err = udp:receive()
                ngx.say("received: ", data)
            ';
        }
    --- udp_listen: 19232
    --- udp_reply: hello world
    --- request
    GET /t
    --- udp_query: hello world
    --- response_body
    received: hello world

=head2 tcp_listen

Just like C<udp_listen>, but starts an embedded TCP server listening on the port specified. For example,

    --- tcp_listen: 12345

Stream-typed unix domain socket is also supported. Just specify the path to the socket file, as in

    --- tcp_listen: /tmp/my-socket.sock

=head2 tcp_no_close

When this section is present, the embedded TCP server (if any) will not close
the current TCP connection.

=head2 tcp_reply_delay

Just like C<udp_reply_delay>, but for the embedded TCP server.

=head2 tcp_reply

Just like C<tcp_reply>, but for the embedded TCP server.

=head2 tcp_query

Just like C<udp_query>, but for the embedded TCP server.

=head2 tcp_query_len

Specifies the expected TCP query received by the embedded TCP server.

If C<tcp_query> is specified, C<tcp_query_len> defaults to the length of the value of C<tcp_query>.

=head2 tcp_shutdown

Shuts down the reading part, writing part, or both in the embedded TCP server as soon as a new connection is established. Its value specifies which part to shut down: 0 for read part only, 1 for write part only, and 2 for both directions.

=head2 raw_request_middle_delay

Delay in sec between sending successive packets in the "raw_request" array
value. Also used when a request is split in packets.

=head2 no_check_leak

Skip the tests in the current test block in the "check leak" testing mode
(i.e, with C<TEST_NGINX_CHECK_LEAK>=1).

=head2 must_die

Test the cases that Nginx must die right after starting. If a value is specified, the exit code must match the specified value.

Normal request and response cycle is not done. But you can still use the
C<error_log> section to check if there is an error message to be seen.

This is meant to test bogus configuration is noticed and given proper
error message. It is normal to see stderr error message when running these tests.

Below is an example:

    === TEST 1: bad "return" directive
    --- config
        location = /t {
            return a b c;
        }
    --- request
        GET /t
    --- must_die
    --- error_log
    invalid number of arguments in "return" directive
    --- no_error_log
    [error]

This configuration ignores C<TEST_NGINX_USE_VALGRIND>
C<TEST_NGINX_USE_STAP> or C<TEST_NGINX_CHECK_LEAK> since there is no point to check other things when the nginx is expected to die right away.

This directive is handled before checking C<TEST_NGINX_IGNORE_MISSING_DIRECTIVES>.

=head1 Environment variables

All environment variables starting with C<TEST_NGINX_> are expanded in the
sections used to build the configuration of the server that tests automatically
starts. The following environment variables are supported by this module:

=head2 TEST_NGINX_VERBOSE

Controls whether to output verbose debugging messages in Test::Nginx. Default to empty.

=head2 TEST_NGINX_BENCHMARK

When set to an non-empty and non-zero value, then the test scaffold enters the benchmarking testing mode by invoking C<weighttp> (for HTTP 1.1 requests) and C<ab> (for HTTP 1.0 requests)
to run each test case with the test request repeatedly.

When specifying a positive number as the value, then this number is used for the total number of repeated requests. For example,

    export TEST_NGINX_BENCHMARK=1000

will result in 1000 repeated requests for each test block. Default to C<100000>.

When a second number is specified (separated from the first number by spaces), then this second number is used for the concurrency level for the benchmark. For example,

    export TEST_NGINX_BENCHMARK='1000 10'

will result in 1000 repeated requests over 10 concurrent connections for each test block. The default concurrency level is 2 (or 1 if the number of requests is 1).

The "benchmark" testing mode will also output to stderr the actual "ab" or "weighttp" command line used by the test scaffold. For example,

    weighttp -c2 -k -n2000 -H 'Host: foo.com' http://127.0.0.1:1984/t

See also the C<TEST_NGINX_BENCHMARK_WARMUP> environment.

This testing mode requires the C<unbuffer> command-line utility from the C<expect> package.

=head2 TEST_NGINX_BENCHMARK_WARMUP

Specify the number of "warm-up" requests performed before the actual benchmark requests for each test block.

The latencies of the warm-up requests never get included in the final benchmark results.

Only meaningful in the "benchmark" testing mode.

See also the C<TEST_NGINX_BENCHMARK> environment.

=head2 TEST_NGINX_CHECK_LEAK

When set to 1, the test scaffold performs the most general memory
leak test by means of calling C<weighttpd>/C<ab> and C<ps>.

Specifically, it starts C<weighttp> (for HTTP 1.1 C<GET> requests) or
C<ab> (for HTTP 1.0 requests) to repeatedly hitting Nginx for
seconds in a sub-process, and then after about 1 second, it will
start sampling the RSS value of the Nginx process by calling
the C<ps> utility every 20 ms. Finally, it will output all
the sample point data and the
line slope of the linear regression result on the 100 sample points.

One typical output for non-leaking test cases:

    t/075-logby.t .. 3/17 TEST 2: log_by_lua_file
    LeakTest: [2176 2176 2176 2176 2176 2176 2176
     2176 2176 2176 2176 2176 2176 2176 2176 2176
     2176 2176 2176 2176 2176 2176 2176 2176 2176
     2176 2176 2176 2176 2176 2176 2176 2176 2176
     2176 2176 2176 2176 2176 2176 2176 2176 2176
     2176 2176 2176 2176 2176 2176 2176 2176 2176
     2176 2176 2176 2176 2176 2176 2176 2176 2176
     2176 2176 2176 2176 2176 2176 2176 2176 2176
     2176 2176 2176 2176 2176 2176 2176 2176 2176
     2176 2176 2176 2176 2176 2176 2176 2176 2176
     2176 2176 2176 2176 2176 2176 2176 2176 2176
     2176 2176 2176]
    LeakTest: k=0.0

and here is an example of leaking:

    TEST 5: ngx.ctx available in log_by_lua (not defined yet)
    LeakTest: [4396 4440 4476 4564 4620 4708 4752
     4788 4884 4944 4996 5032 5080 5132 5188 5236
     5348 5404 5464 5524 5596 5652 5700 5776 5828
     5912 5964 6040 6108 6108 6316 6316 6584 6672
     6672 6752 6820 6912 6912 6980 7064 7152 7152
     7240 7340 7340 7432 7508 7508 7600 7700 7700
     7792 7896 7896 7992 7992 8100 8100 8204 8296
     8296 8416 8416 8512 8512 8624 8624 8744 8744
     8848 8848 8968 8968 9084 9084 9204 9204 9324
     9324 9444 9444 9584 9584 9704 9704 9832 9832
     9864 9964 9964 10096 10096 10488 10488 10488
     10488 10488 11052 11052]
    LeakTest: k=64.1

Even very small leaks can be amplified and caught easily by this
testing mode because their slopes will usually be far above C<1.0>.

For now, only C<GET>, C<POST>, C<PUT>, and C<HEAD> requests are supported
(due to the limited HTTP support in both C<ab> and C<weighttp>).
Other methods specified in the test cases will turn to C<GET> with force.

The tests in this mode will always succeed because this mode also
enforces the "dry-run" mode.

Test blocks carrying the "--- no_check_leak" directive will be skipped in this testing mode.

=head2 TEST_NGINX_USE_HUP

When set to 1, the test scaffold will try to send C<HUP> signal to the
Nginx master process to reload the config file between
successive test blocks (but not successive C<repeast_each>
sub-tests within the same test block). When this environment is set
to 1, it will also enforce the "master_process on" config line
in the F<nginx.conf> file,
because Nginx is buggy in processing HUP signal when the master process is off.

=head2 TEST_NGINX_POSTPONE_OUTPUT

Defaults to empty. This environment takes positive integer numbers as its value and it will cause the auto-generated nginx.conf file to have a "postpone_output" setting in the http {} block.

For example, setting TEST_NGINX_POSTPONE_OUTPUT to 1 will have the following line in nginx.conf's http {} block:

    postpone_output 1;

and it will effectively disable the write buffering in nginx's ngx_http_write_module.

=head2 TEST_NGINX_NO_CLEAN

When this environment is set to 1, it will prevent the test scaffold from quitting the Nginx server
at the end of the run. This is very useful when you want to use other tools like gdb or curl
inspect the Nginx server manually afterwards.

=head2 TEST_NGINX_NO_NGINX_MANAGER

Defaults to 0. If set to 1, Test::Nginx module will not manage
(configure/start/stop) the C<nginx> process. Can be useful to run tests
against an already configured (and running) nginx server.

=head2 TEST_NGINX_NO_SHUFFLE

Defaults to 0. If set to 1, will make sure the tests are run in the order
they appear in the test file (and not in random order).

=head2 TEST_NGINX_USE_VALGRIND

If set, Test::Nginx will start nginx with valgrind with the the value of this environment as the options.

Nginx is actually started with
C<valgrind -q $TEST_NGINX_USE_VALGRIND --gen-suppressions=all --suppressions=valgrind.suppress>,
the suppressions option being used only if there is actually
a valgrind.suppress file.

If this environment is set to the number C<1> or any other
non-zero numbers, then it is equivalent to taking the value
C<--tool=memcheck --leak-check=full>.

=head2 TEST_NGINX_USE_STAP

When set to true values (like 1), the test scaffold will use systemtap to instrument the nginx
process.

You can specify the stap script in the C<stap> section.

Note that you need to use the C<stap-nginx> script from the C<nginx-dtrace> project.

=head2 TEST_NGINX_STAP_OUT

You can specify the output file for the systemtap tool. By default, a random file name
under the system temporary directory is generated.

It's common to specify C<TEST_NGINX_STAP_OUT=/dev/stderr> when debugging.

=head2 TEST_NGINX_BINARY

The command to start nginx. Defaults to C<nginx>. Can be used as an alternative
to setting C<PATH> to run a specific nginx instance.

=head2 TEST_NGINX_LOG_LEVEL

Value of the last argument of the C<error_log> configuration directive.
Defaults to C<debug>.

=head2 TEST_NGINX_MASTER_PROCESS

Value of the C<master_process> configuration directive. Defaults to C<off>.

=head2 TEST_NGINX_SERVER_PORT

Value of the port the server started by Test::Nginx will listen to. If not
set, C<TEST_NGINX_PORT> is used. If C<TEST_NGINX_PORT> is not set,
then C<1984> is used. See below for typical use.

=head2 TEST_NGINX_CLIENT_PORT

Value of the port Test::Nginx will direct requests to. If not
set, C<TEST_NGINX_PORT> is used. If C<TEST_NGINX_PORT> is not set,
then C<1984> is used. A typical use of this feature is to test extreme
network conditions by adding a "proxy" between Test::Nginx and nginx
itself. This is described in the C<etcproxy integration> section of this
module README.

=head2 TEST_NGINX_PORT

A shortcut for setting both C<TEST_NGINX_CLIENT_PORT> and
C<TEST_NGINX_SERVER_PORT>.

=head2 TEST_NGINX_SLEEP

How much time (in seconds) should Test::Nginx sleep between two calls to C<syswrite> when
sending request data. Defaults to 0.

=head2 TEST_NGINX_FORCE_RESTART_ON_TEST

Defaults to 1. If set to 0, Test::Nginx will not restart the nginx
server when the config does not change between two tests.

=head2 TEST_NGINX_SERVROOT

The root of the nginx "hierarchy" (where you find the conf, *_tmp and logs
directories). This value will be used with the C<-p> option of C<nginx>.
Defaults to appending C<t/servroot> to the current directory.

=head2 TEST_NGINX_IGNORE_MISSING_DIRECTIVES

If set to 1 will SKIP all tests which C<config> sections resulted in a
C<unknown directive> when trying to start C<nginx>. Useful when you want to
run tests on a build of nginx that does not include all modules it should.
By default, these tests will FAIL.

=head2 TEST_NGINX_EVENT_TYPE

This environment can be used to specify a event API type to be used by Nginx. Possible values are C<epoll>, C<kqueue>, C<select>, C<rtsig>, C<poll>, and others.

For example,

    $ TEST_NGINX_EVENT_TYPE=select prove -r t

=head2 TEST_NGINX_ERROR_LOG

Error log files from all tests will be appended to the file specified with
this variable. There is no default value which disables the feature. This
is very useful when debugging. By default, each test triggers a start/stop
cycle for C<nginx>. All logs are removed before each restart, so you can
only see the logs for the last test run (which you usually do not control
except if you set C<TEST_NGINX_NO_SHUFFLE=1>). With this, you accumulate
all logs into a single file that is never cleaned up by Test::Nginx.

=head1 Samples

You'll find live samples in the following Nginx 3rd-party modules:

=over

=item ngx_echo

L<http://github.com/agentzh/echo-nginx-module>

=item ngx_chunkin

L<http://wiki.nginx.org/NginxHttpChunkinModule>

=item ngx_memc

L<http://wiki.nginx.org/NginxHttpMemcModule>

=item ngx_drizzle

L<http://github.com/chaoslawful/drizzle-nginx-module>

=item ngx_rds_json

L<http://github.com/agentzh/rds-json-nginx-module>

=item ngx_xss

L<http://github.com/agentzh/xss-nginx-module>

=item ngx_srcache

L<http://github.com/agentzh/srcache-nginx-module>

=item ngx_lua

L<http://github.com/chaoslawful/lua-nginx-module>

=item ngx_set_misc

L<http://github.com/agentzh/set-misc-nginx-module>

=item ngx_array_var

L<http://github.com/agentzh/array-var-nginx-module>

=item ngx_form_input

L<http://github.com/calio/form-input-nginx-module>

=item ngx_iconv

L<http://github.com/calio/iconv-nginx-module>

=item ngx_set_cconv

L<http://github.com/liseen/set-cconv-nginx-module>

=item ngx_postgres

L<http://github.com/FRiCKLE/ngx_postgres>

=item ngx_coolkit

L<http://github.com/FRiCKLE/ngx_coolkit>

=back

=head1 SOURCE REPOSITORY

This module has a Git repository on Github, which has access for all.

    http://github.com/agentzh/test-nginx

If you want a commit bit, feel free to drop me a line.

=head1 DEBIAN PACKAGES

António P. P. Almeida is maintaining a Debian package for this module
in his Debian repository: L<http://debian.perusio.net>

=head1 Community

=head2 English Mailing List

The C<openresty-en> mailing list is for English speakers: L<https://groups.google.com/group/openresty-en>

=head2 Chinese Mailing List

The C<openresty> mailing list is for Chinese speakers: L<https://groups.google.com/group/openresty>

=head1 AUTHORS

Yichun "agentzh" Zhang (章亦春) C<< <agentzh@gmail.com> >>, CloudFlare Inc.

Antoine BONAVITA C<< <antoine.bonavita@gmail.com> >>

=head1 COPYRIGHT & LICENSE

Copyright (c) 2009-2014, Yichun Zhang C<< <agentzh@gmail.com> >>, CloudFlare Inc.

Copyright (c) 2011-2012, Antoine BONAVITA C<< <antoine.bonavita@gmail.com> >>.

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

L<Test::Nginx::LWP>, L<Test::Base>.

