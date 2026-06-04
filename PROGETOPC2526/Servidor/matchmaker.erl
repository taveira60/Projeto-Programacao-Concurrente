-module(matchmaker).
-export([start/1]).

start(TopM) ->
    spawn(fun() -> loop([], #{}, TopM) end).
% PID: Matchmaker_PID

loop(QNamesPids, Games, TopM) ->
    receive
        % Jogador entra na fila
        {join_queue, From, Username} ->
            % if username in queue
            case lists:any(fun({_, Pid}) -> Pid =:= From end, QNamesPids) of
                true ->
                    From ! {error, already_in_queue},
                    loop(QNamesPids, Games, TopM);
                false ->
                    NewQueue = QNamesPids ++ [{Username, From}],
                    From ! ok,
                    %[TRIGGER] pode acontecer um novo jogo
                    {FinalQueue, FinalGames} = start_game(NewQueue, Games),
                    loop(FinalQueue, FinalGames, TopM)
            end;
        %sai da fila
        {leave_queue, From, _} ->
            case lists:any(fun({_, Pid}) -> Pid =:= From end, QNamesPids) of
                true ->
                    NewQueue = lists:filter(fun({_, Pid}) -> Pid =/= From end, QNamesPids),
                    From ! ok,
                    loop(NewQueue, Games, TopM);
                false ->
                    From ! ok,
                    loop(QNamesPids, Games, TopM)
            end;
        %Avisar o mastchmaker que um jogo terminou, ou seja no caso de isto estar cheio pode voltar a tentar encher um servidor
        {game_finished, GameId, Winner} ->
            io:format("Jogo ~p terminado. Vencedor: ~p~n", [GameId, Winner]),
            case Winner of
                no_winner -> ok;
                {Name, Score} -> TopM ! {add_winner, Name, Score}
            end,
            NewGames = maps:remove(GameId, Games),
            {FinalQueue, FinalGames} = start_game(QNamesPids, NewGames),
            loop(FinalQueue, FinalGames, TopM)
    end.

%Começar jogos
start_game(QNamesPids, Games) ->
    % min de jogadores: 3 e max de salas: 4
    case {length(QNamesPids) >= 3, maps:size(Games) < 4} of % pus pra testar dps mudo 
        {true, true} ->
            N =
                case length(QNamesPids) >= 4 of
                    true -> 4;
                    false -> 3
                end,

            SelectedPlayers = lists:sublist(QNamesPids, N),
            RestPlayers = lists:nthtail(N, QNamesPids),

            ValidPlayers = lists:filter(
                fun({_, Pid}) -> is_process_alive(Pid) end, SelectedPlayers
            ),

            case length(ValidPlayers) >= 3 of
                false ->
                    InvalidPlayers = SelectedPlayers -- ValidPlayers,
                    io:format("Jogadores mortos removidos: ~p~n", [InvalidPlayers]),
                    start_game(ValidPlayers ++ RestPlayers, Games);
                true ->
                    GamePid = game_session:start(ValidPlayers, self()),
                    SelectedPids = [Pid || {_, Pid} <- ValidPlayers],
                    [Pid ! {matchmaker, {game_start, GamePid}} || Pid <- SelectedPids],
                    SelectedNames = [Name || {Name, _} <- ValidPlayers],
                    io:format("Novo jogo (~p) com jogadores: ~p~n", [GamePid, SelectedNames]),
                    NewGames = maps:put(GamePid, ValidPlayers, Games),
                    start_game(RestPlayers, NewGames)
            end;
        _ ->
            {QNamesPids, Games}
    end.
