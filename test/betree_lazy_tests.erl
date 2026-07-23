-module(betree_lazy_tests).

-include_lib("eunit/include/eunit.hrl").

-record(ev, {a, b, c}).

prepare_flat_test() ->
    Domains = [[
        {a, int, disallow_undefined},
        {b, int, disallow_undefined}
    ]],
    {ok, Betree} = erl_betree:betree_make(Domains),
    ok = erl_betree:betree_add_sub(Betree, 1, [], <<"a = 1">>),
    ok = erl_betree:betree_prepare_flat(Betree),
    ok.

basic_lazy_no_unfetched_test() ->
    Domains = [[
        {a, int, disallow_undefined},
        {b, int, disallow_undefined}
    ]],
    {ok, Betree} = erl_betree:betree_make(Domains),
    ok = erl_betree:betree_add_sub(Betree, 1, [], <<"a = 1">>),
    ok = erl_betree:betree_prepare_flat(Betree),
    Event = [{ev, 1, 2}],
    {ok, Matched} = erl_betree:betree_search_lazy(Betree, Event),
    ?assertEqual([1], Matched).

basic_lazy_test() ->
    Domains = [[
        {a, int, disallow_undefined},
        {b, int, disallow_undefined},
        {c, int, disallow_undefined}
    ]],
    {ok, Betree} = erl_betree:betree_make(Domains),
    ok = erl_betree:betree_add_sub(Betree, 1, [], <<"a = 1">>),
    ok = erl_betree:betree_add_sub(Betree, 2, [], <<"b = 2">>),
    ok = erl_betree:betree_add_sub(Betree, 3, [], <<"c = 3">>),
    ok = erl_betree:betree_prepare_flat(Betree),

    %% Full event - all vars present
    Event = [#ev{a = 1, b = 2, c = 3}],
    {ok, Matched} = erl_betree:betree_search_lazy(Betree, Event),
    ?assertEqual(lists:sort(Matched), [1, 2, 3]),

    %% Lazy: b is unfetched
    EventLazy = [#ev{a = 1, b = unfetched, c = 3}],
    case erl_betree:betree_search_lazy(Betree, EventLazy) of
        {continue, Cont, PartialMatched} ->
            ?assert(is_list(PartialMatched)),
            %% Provide the missing var: b (index 1) = 2
            {ok, Matched2} = erl_betree:betree_search_continue(Betree, Cont, [{1, 2}]),
            AllMatched = lists:sort(PartialMatched ++ Matched2),
            ?assertEqual(AllMatched, [1, 2, 3]);
        {ok, _} ->
            %% Should not complete without b
            ?assert(false)
    end.

lazy_no_yield_test() ->
    Domains = [[
        {a, int, disallow_undefined},
        {b, int, disallow_undefined}
    ]],
    {ok, Betree} = erl_betree:betree_make(Domains),
    ok = erl_betree:betree_add_sub(Betree, 1, [], <<"a = 5">>),
    ok = erl_betree:betree_prepare_flat(Betree),

    %% No unfetched vars - should complete immediately
    Event = [{ev, 5, 10}],
    {ok, Matched} = erl_betree:betree_search_lazy(Betree, Event),
    ?assertEqual([1], Matched).

lazy_multiple_yields_test() ->
    Domains = [[
        {a, int, disallow_undefined},
        {b, int, disallow_undefined},
        {c, int, disallow_undefined}
    ]],
    {ok, Betree} = erl_betree:betree_make(Domains),
    ok = erl_betree:betree_add_sub(Betree, 1, [], <<"a = 1 and b = 2">>),
    ok = erl_betree:betree_add_sub(Betree, 2, [], <<"c = 3">>),
    ok = erl_betree:betree_prepare_flat(Betree),

    %% Both b and c are unfetched
    EventLazy = [#ev{a = 1, b = unfetched, c = unfetched}],
    Result = erl_betree:betree_search_lazy(Betree, EventLazy),
    ?assertMatch({continue, _, _}, Result),
    {continue, Cont1, Matched1} = Result,

    %% Provide b = 2
    Result2 = erl_betree:betree_search_continue(Betree, Cont1, [{1, 2}]),
    case Result2 of
        {ok, Matched2} ->
            AllMatched = lists:sort(Matched1 ++ Matched2),
            ?assertEqual([1, 2], AllMatched);
        {continue, Cont2, Matched2} ->
            %% Provide c = 3
            {ok, Matched3} = erl_betree:betree_search_continue(Betree, Cont2, [{2, 3}]),
            AllMatched = lists:sort(Matched1 ++ Matched2 ++ Matched3),
            ?assertEqual([1, 2], AllMatched)
    end.

continue_betree_mismatch_test() ->
    Domains = [[
        {a, int, disallow_undefined},
        {b, int, disallow_undefined}
    ]],
    {ok, Betree1} = erl_betree:betree_make(Domains),
    ok = erl_betree:betree_add_sub(Betree1, 1, [], <<"a = 1 and b = 2">>),
    ok = erl_betree:betree_prepare_flat(Betree1),

    {ok, Betree2} = erl_betree:betree_make(Domains),
    ok = erl_betree:betree_add_sub(Betree2, 1, [], <<"a = 1">>),
    ok = erl_betree:betree_prepare_flat(Betree2),

    %% Get continuation from Betree1
    EventLazy = [{ev, 1, unfetched}],
    {continue, Cont, _} = erl_betree:betree_search_lazy(Betree1, EventLazy),

    %% Continue with Betree2 - should fail with badarg
    ?assertError(badarg, erl_betree:betree_search_continue(Betree2, Cont, [{1, 2}])).

continue_stats_mismatch_test() ->
    Domains = [[
        {a, int, disallow_undefined},
        {b, int, disallow_undefined}
    ]],
    {ok, Betree1} = erl_betree:betree_make(Domains),
    ok = erl_betree:betree_add_sub(Betree1, 1, g1, [], <<"a = 1 and b = 2">>),
    ok = erl_betree:betree_prepare_flat(Betree1),

    {ok, Betree2} = erl_betree:betree_make(Domains),
    ok = erl_betree:betree_add_sub(Betree2, 1, g1, [], <<"a = 1">>),
    ok = erl_betree:betree_prepare_flat(Betree2),

    %% Get continuation from Betree1
    EventLazy = [{ev, 1, unfetched}],
    {continue, Cont, _} = erl_betree:betree_search_lazy(Betree1, EventLazy),

    %% Continue with stats accumulator from Betree2 - should fail with badarg
    {ok, AccRef} = erl_betree:betree_stats_start(Betree2),
    ?assertError(badarg, erl_betree:betree_search_continue(AccRef, Cont, [{1, 2}])),
    erl_betree:betree_stats_stop(AccRef).
