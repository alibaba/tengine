# vi:ft=

use 5.10.1;
use Test::Base;
use RecvUntil;

plan tests => 1 * blocks();

run {
    my $block = shift;
    my $name = $block->name;
    my $pat = $block->pat // die "$name: No --- pat found";
    my $txt = $block->txt // die "$name: No --- txt found";

    my $expected = $block->out // die "$name: No --- out found";

    my $it = RecvUntil::recv_until($pat);
    is $it->($txt), $expected, "$name: output ok";
};

__DATA__

=== TEST 1:
--- pat: abcabd
--- txt: abcabcabd
--- out: abc



=== TEST 2:
--- pat: aa
--- txt: abcabcaad
--- out: abcabc



=== TEST 3:
--- pat: ab
--- txt: bbcabcaad
--- out: bbc



=== TEST 4:
--- pat: aaa
--- txt: abaabcaaaef
--- out: abaabc



=== TEST 5:
--- pat: aaaaad
--- txt: baaaaaaaaeaaaaaaadf
--- out: baaaaaaaaeaa



=== TEST 6:
--- pat: abacadae
--- txt: a
--- out:



=== TEST 7:
--- pat: abacadae
--- txt: ababacadae
--- out: ab



=== TEST 8:
--- pat: abacadae
--- txt: abacabacadae
--- out: abac



=== TEST 9:
--- pat: abacadae
--- txt: abaabacadae
--- out: aba



=== TEST 10:
--- pat: abacadae
--- txt: abacadabacadae
--- out: abacad



=== TEST 11:
--- pat: abcabdabcabe
--- txt: abcabdabcabdabcabe
--- out: abcabd



=== TEST 12:
--- pat: abcabdabcabe
--- txt: abcabdabcabcabdabcabe
--- out: abcabdabc



=== TEST 13:
--- pat: abcabdabcabe
--- txt: abcabcabdabcabe
--- out: abc



=== TEST 14:
--- pat: abcabdabcabe
--- txt: ababcabdabcabe
--- out: ab



=== TEST 15:
--- pat: abcdef
--- txt: abcabcdef
--- out: abc



=== TEST 16:
--- pat: -- abc
--- txt: ---- abc
--- out: --



=== TEST 17:
--- pat: yz--ababyz
--- txt: 
--- out: --
--- SKIP

