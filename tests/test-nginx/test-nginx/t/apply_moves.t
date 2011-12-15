# Unit tests for Test::Nginx::Socket::parse_request
use Test::Nginx::Socket tests => 6;

is_deeply(Test::Nginx::Socket::apply_moves(['foo'], [{d => 2}]),
          ['o'], "Basic delete");
is_deeply(Test::Nginx::Socket::apply_moves(['GIT /'], [{s_s => 3, s_v => 'GET'}]),
          ['GET /'], "Basic substitute");
is_deeply(Test::Nginx::Socket::apply_moves(['GI', 'T /'], [{s_s => 3, s_v => 'GET'}]),
          ['GE', 'T /'], "Substitute on border");
is_deeply(Test::Nginx::Socket::apply_moves(['/'], [{s_s => 0, s_v => 'GET '}]),
          ['GET /'], "Append");
is_deeply(Test::Nginx::Socket::apply_moves(['GET'],
                                           [{s_s => 3, s_v => 'GET '},
                                            {d => 0},
                                            {s_s => 0, s_v => '/ '},
                                            {d => 0},
                                            {s_s => 0, s_v => 'HTTP/1.1'}]),
          ['GET / HTTP/1.1'], "Simple GET");
is_deeply(Test::Nginx::Socket::apply_moves(['GE', 'T'],
                                           [{s_s => 3, s_v => 'GET '},
                                            {d => 0},
                                            {s_s => 0, s_v => '/ '},
                                            {d => 0},
                                            {s_s => 0, s_v => 'HTTP/1.1'}]),
          ['GE', 'T / HTTP/1.1'], "Split GET");
          