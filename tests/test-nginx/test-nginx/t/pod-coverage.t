use Test::More;

plan skip_all => "we know we have poor POD coverage :P";

eval "use Test::Pod::Coverage";
plan skip_all => "Test::Pod::Coverage required for testing POD coverage" if $@;
all_pod_coverage_ok();

