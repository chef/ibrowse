%%% File    : ibrowse_http_client_test.erl
%%% Author  : Mark Anderson
%%% Description : Test ibrowse_http_client
%%% Created : 2018-09-30

-module(ibrowse_http_client_test).

-include_lib("ibrowse/include/ibrowse.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(IPV4_ADDRESS, "127.0.0.1").
-define(IPV6_ADDRESS, "::1").
-define(IPV4_ONLY_HOST, "ipv4.test-ipv6.noroutetohost.net").
-define(IPV6_ONLY_HOST, "ipv6.test-ipv6.noroutetohost.net").
-define(IPV46_HOST, "www.google.com").

-define(TIMEOUT, 500).
-define(DEFAULT_SOCK_OPTIONS, [{nodelay, true}, binary, {active, false}]).
-define(DEFAULT_SOCK_OPTIONS_WITH_IPV6, [{nodelay, true}, binary, {active, false}, inet6]).

do_connect_test_() ->
    [
     { "An IPv4 addresss connects with IPv4 with the default",
       ?_assertMatch({ok, _}, ibrowse_http_client:do_connect(?IPV4_ADDRESS, 80, [], {}, ?TIMEOUT))
     },
     { "An IPv4 address connects even when IPv6 is preferred",
       ?_assertMatch({ok, _}, ibrowse_http_client:do_connect(?IPV4_ADDRESS, 80, [prefer_ipv6], ?TIMEOUT))
     },
     { "An IPv6 address returns as IPv6 with the default",
       ?_assertMatch(?DEFAULT_SOCK_OPTIONS_WITH_IPV6, ibrowse_http_client:do_connect(?IPV6_ONLY_HOST, 80, [], {}, ?TIMEOUT))
     },
     { "An IPV6 address returns as IPv6 when IPv6 is preferred",
       ?_assertMatch(?DEFAULT_SOCK_OPTIONS_WITH_IPV6, ibrowse_http_client:do_connect(?IPV6_ONLY_HOST, 80, [prefer_ipv6], {}, ?TIMEOUT))
     },

     { "A hostname that resolves IPv4 only returns as IPv4 with the default",
       ?_assertMatch(?DEFAULT_SOCK_OPTIONS, ibrowse_http_client:do_connect(?IPV4_ONLY_HOST, 80, [], {}, ?TIMEOUT))
     },
     { "A hostname that resolves IPv4 only returns as IPv4 even when IPv6 is preferred",
       ?_assertMatch(?DEFAULT_SOCK_OPTIONS, ibrowse_http_client:do_connect(?IPV4_ONLY_HOST, 80, [prefer_ipv6], {}, ?TIMEOUT))
     },
     { "A hostname that resolves IPv6 only returns as IPv6 with the default",
       ?_assertMatch(?DEFAULT_SOCK_OPTIONS_WITH_IPV6, ibrowse_http_clientL:do_connect(?IPV6_ONLY_HOST, 80, [], {}, ?TIMEOUT))
     },
     { "A hostname that resolves IPv6 only returns as IPv6 when IPv6 is preferred",
       ?_assertMatch(?DEFAULT_SOCK_OPTIONS_WITH_IPV6, ibrowse_http_client:do_connect(?IPV6_ONLY_HOST, 80, [prefer_ipv6], {}, ?TIMEOUT))
     },
     { "A hostname that resolves both IPv4 and 6 returns as IPv4 with the default",
       ?_assertMatch(?DEFAULT_SOCK_OPTIONS, ibrowse_http_client:do_connect(?IPV46_HOST, 80, [], {}, ?TIMEOUT))
     },
     { "A hostname that resolves both IPv4 and 6 returns as IPv6 when IPv6 is preferred",
       ?_assertMatch(?DEFAULT_SOCK_OPTIONS_WITH_IPV6, ibrowse_http_client:do_connect(?IPV46_HOST, 80, [prefer_ipv6], {}, ?TIMEOUT))
     }
    ].


get_sock_options_test_() ->
    [
     { "An IPv4 addresss returns as IPv4 with the default",
       ?_assertMatch(?DEFAULT_SOCK_OPTIONS, ibrowse_http_client:get_sock_options(?IPV4_ADDRESS, [], []))
     },
     { "An IPv4 address returns as IPv4 even when IPv6 is preferred",
       ?_assertMatch(?DEFAULT_SOCK_OPTIONS, ibrowse_http_client:get_sock_options(?IPV4_ADDRESS, [prefer_ipv6], []))
     },
     { "An IPv6 address returns as IPv6 with the default",
       ?_assertMatch(?DEFAULT_SOCK_OPTIONS_WITH_IPV6, ibrowse_http_client:get_sock_options(?IPV6_ONLY_HOST, [], []))
     },
     { "An IPV6 address returns as IPv6 when IPv6 is preferred",
       ?_assertMatch(?DEFAULT_SOCK_OPTIONS_WITH_IPV6, ibrowse_http_client:get_sock_options(?IPV6_ONLY_HOST, [prefer_ipv6], []))
     },

     { "A hostname that resolves IPv4 only returns as IPv4 with the default",
       ?_assertMatch(?DEFAULT_SOCK_OPTIONS, ibrowse_http_client:get_sock_options(?IPV4_ONLY_HOST, [], []))
     },
     { "A hostname that resolves IPv4 only returns as IPv4 even when IPv6 is preferred",
       ?_assertMatch(?DEFAULT_SOCK_OPTIONS, ibrowse_http_client:get_sock_options(?IPV4_ONLY_HOST, [prefer_ipv6], []))
     },
     { "A hostname that resolves IPv6 only returns as IPv6 with the default",
       ?_assertMatch(?DEFAULT_SOCK_OPTIONS_WITH_IPV6, ibrowse_http_client:get_sock_options(?IPV6_ONLY_HOST, [], []))
     },
     { "A hostname that resolves IPv6 only returns as IPv6 when IPv6 is preferred",
       ?_assertMatch(?DEFAULT_SOCK_OPTIONS_WITH_IPV6, ibrowse_http_client:get_sock_options(?IPV6_ONLY_HOST, [prefer_ipv6], []))
     },
     { "A hostname that resolves both IPv4 and 6 returns as IPv4 with the default",
       ?_assertMatch(?DEFAULT_SOCK_OPTIONS, ibrowse_http_client:get_sock_options(?IPV46_HOST, [], []))
     },
     { "A hostname that resolves both IPv4 and 6 returns as IPv6 when IPv6 is preferred",
       ?_assertMatch(?DEFAULT_SOCK_OPTIONS_WITH_IPV6, ibrowse_http_client:get_sock_options(?IPV46_HOST, [prefer_ipv6], []))
     }
    ].

is_ipv6_host_test_() ->
    [{ "An IPv4 address returns false",
       ?_assertMatch(false, ibrowse_http_client:is_ipv6_host(?IPV4_ADDRESS))
     },
     { "An IPv6 address returns true",
       ?_assertMatch(true, ibrowse_http_client:is_ipv6_host(?IPV6_ADDRESS))
     },
     { "An hostname that resolves IPv4 only returns false",
       ?_assertMatch(false, ibrowse_http_client:is_ipv6_host(?IPV4_ONLY_HOST))
     },
     { "A hostname that resolves IPv6 only returns true",
       ?_assertMatch(true, ibrowse_http_client:is_ipv6_host(?IPV6_ONLY_HOST))
     },
     { "A hostname that resolves both IPv4 and 6 returns true",
       ?_assertMatch(true, ibrowse_http_client:is_ipv6_host(?IPV46_HOST))
     }
    ].
