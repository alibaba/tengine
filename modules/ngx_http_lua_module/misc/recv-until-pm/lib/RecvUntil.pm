package RecvUntil;

use strict;
use warnings;

sub recv_until {
    my ($pat) = @_;

    my $len = length $pat;
    my @backtracks;

    for (my $i = 1; $i <= $len - 1; $i++) {
        my $matched_prefix_len = 1;
        while ($matched_prefix_len <= $len - $i - 1) {
            #while (1) {
            #my $left = $len - $i;
            #warn "left: $i: $len: ", $len - 1 - $i, "\n";
            #warn "matched_prefix_len: $matched_prefix_len\n";

            #while (1) {
            my $prefix = substr($pat, 0, $matched_prefix_len);
            my $next = substr($pat, $matched_prefix_len, 1);

            my $prefix2 = substr($pat, $i, $matched_prefix_len);
            my $next2 = substr($pat, $i + $matched_prefix_len, 1);

            #warn "$i: global prefix $prefix $next\n";
            #warn "$i: local prefix $prefix2 $next2\n";

            if ($prefix2 eq $prefix) {
                if ($next2 eq $next) {
                    $matched_prefix_len++;
                    next;
                }

                #warn "$matched_prefix_len: $prefix: found match at $i (next $next, next2 $next2)\n";
                my $cur_state = $i + $matched_prefix_len;
                my $new_state = $matched_prefix_len + 1;

                my $matched = substr($pat, 0, $cur_state);

                my $chain = $backtracks[$cur_state - 2];
                if (!$chain) {
                    $chain = [];
                    $backtracks[$cur_state - 2] = $chain;
                }

                my $found = 0;
                for my $rec (@$chain) {
                    if ($rec->{char} eq $next) {
                        $found = 1;

                        if ($rec->{new_state} < $new_state) {
                            warn "overriding...\n";
                            $rec->{new_state} = $new_state;
                        }
                    }
                }

                if (!$found) {
                    warn "on state $cur_state ($matched), if next is '$next', ",
                        "then backtrack to state $new_state ($prefix$next)\n";

                    push @$chain, { char => $next, new_state => $new_state };
                }

                #if ($matched_prefix_len > 1) {
                #$i += $matched_prefix_len - 1;
                #}

                last;
            }

            last;
        }
    }

    return sub {
        my ($txt) = @_;

        my $max_state = length $pat;
        my $len = length $txt;
        my $state = 0;
        my $ret = '';

        for (my $i = 0; $i < $len; $i++) {
            # read the char
            my $c = substr($txt, $i, 1);

            #warn "$state: read char at $i: $c\n";
            #warn "matched: $ret\n";

            my $expected = substr($pat, $state, 1);
            if ($expected eq $c) {
                #warn "matched the char in pattern.\n";
                $state++;

                if ($state == $max_state) {
                    last;
                }

                next;
            }

            if ($state == 0) {
                #warn "did not match the first char in pattern\n";
                $ret .= $c;
                next;
            }

            my $old_state;
            my $matched;
            my $chain = $backtracks[$state - 2];
            for my $rec (@$chain) {
                if ($rec->{char} eq $c) {
                    $old_state = $state;
                    $state = $rec->{new_state};
                    #warn "matched the char for backtracking to state $state\n";
                    $matched = 1;
                    last;
                }
            }

            if (!$matched) {
                $ret .= substr($pat, 0, $state);
                $state = 0;
                redo;
            }

            $ret .= substr($pat, 0, $old_state + 1 - $state);
            next;
        }

        return $ret;
    };
}

1;
