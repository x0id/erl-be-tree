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
        {continue, Cont, NeededVars} ->
            ?assert(lists:member(1, NeededVars)),
            %% Provide the missing var: b (index 1) = 2
            {ok, Matched2} = erl_betree:betree_search_continue(Cont, [{1, 2}]),
            ?assertEqual(lists:sort(Matched2), [1, 2, 3]);
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
    {continue, Cont1, Needed1} = Result,

    %% Provide only the first needed var
    [FirstNeeded | _] = Needed1,
    Val = case FirstNeeded of
        1 -> 2; % b = 2
        2 -> 3  % c = 3
    end,
    Result2 = erl_betree:betree_search_continue(Cont1, [{FirstNeeded, Val}]),
    case Result2 of
        {ok, Matched} ->
            ?assert(length(Matched) > 0);
        {continue, Cont2, Needed2} ->
            [SecondNeeded | _] = Needed2,
            Val2 = case SecondNeeded of
                1 -> 2;
                2 -> 3
            end,
            {ok, Matched2} = erl_betree:betree_search_continue(Cont2, [{SecondNeeded, Val2}]),
            ?assertEqual(lists:sort(Matched2), [1, 2])
    end.
