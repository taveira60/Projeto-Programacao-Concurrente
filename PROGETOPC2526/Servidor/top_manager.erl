-module(top_manager).
-export([start/0]).

start() ->
    spawn(fun() -> loop([]) end).

%% Loop principal do processo top_manager
loop(Scores) ->
    receive
        %% Recebe um novo vencedor para adicionar/atualizar
        {add_winner, Username, Score} ->
            NewScores = lists:keystore(Username, 1, Scores, {Username, Score}),
            loop(NewScores);

        %% Recebe um pedido do top atual
        {get_top, From} ->
            Sorted = lists:reverse(lists:keysort(2, Scores)),
            From ! {top, Sorted},
            loop(Scores)
    end.