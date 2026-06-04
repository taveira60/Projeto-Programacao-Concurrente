-module(game_session).
-export([start/2, send_input/3,update/1]).

% Players = [{Username, Pid}]
start(Players, MatchmakerPid) ->
    % com spawn corre em paralelo tava a dar problemas
    spawn(fun() -> init(Players, MatchmakerPid) end).

% API para receber input (do client_handler depois) perfeito
send_input(GamePid, Username, Input) ->
    GamePid ! {input, Username, Input}.

%Cria um jogo novo. Cria cada jogo como sondo único com um GameId único através da função make_ref
init(Players, MatchmakerPid) ->
    GameId = make_ref(),
    io:format("Game ~p started with players: ~p~n", [GameId, Players]),
    State = #{
        id => GameId,
        players => init_players(Players),
        objects => init_objetct(10, 5),
        start_time => erlang:monotonic_time(second)
    },
    erlang:send_after(50, self(), update_tick),
    loop(State, MatchmakerPid).

loop(State, MatchmakerPid) ->
    receive
        {input, Username, Command} ->
            NewState = handle_input(State, Username, Command),
            loop(NewState, MatchmakerPid);
        %% ~20 FPS ////
        update_tick ->
            erlang:send_after(50, self(), update_tick),
            Now = erlang:monotonic_time(second),
            Start = maps:get(start_time, State),
            UpdatedState = update(State),
            broadcast(UpdatedState),
            case Now - Start >= 120 of
                true ->
                    io:format("Game ~p finished~n", [maps:get(id, State)]),
                    % Enviar game_over a todos os jogadores
                    Players = maps:get(players, UpdatedState),
                    % Calcular vencedor
                    ScoresList = [{Username, maps:get(score, PData)} || {Username, PData} <- maps:to_list(Players)],
                    Sorted = lists:reverse(lists:keysort(2, ScoresList)),
                    Winner = case Sorted of
                        [{WinnerName, WinnerScore}, {_, SecondScore} | _] when SecondScore =:= WinnerScore ->
                            no_winner;
                        [{WinnerName, WinnerScore} | _] ->
                            {WinnerName, WinnerScore};
                        [] ->
                            no_winner
                    end,
                    % Enviar game_over a todos os jogadores
                    [Pid ! {game_over, self()} || {_, #{pid := Pid}} <- maps:to_list(Players)],
                    MatchmakerPid ! {game_finished, self(), Winner};
                false ->
                    loop(UpdatedState, MatchmakerPid)
            end
    end.

init_players(Players) ->
    lists:foldl(
        fun({Username, Pid}, AccMap) ->
            Mass = 800.0,
            PData = #{
                pos => {rand:uniform() * 500, rand:uniform() * 500},
                vel => {0.0, 0.0},
                angle => 0.0,
                ang_vel => 0.0,
                mass => Mass,
                torque => 10.00,
                force => 40.00,
                score => 0,
                % guardamos o raio para o futuro
                radius => math:sqrt(Mass / math:pi()),
                pid => Pid
            },
            maps:put(Username, PData, AccMap)
        end,
        #{},
        Players
    ).

init_objetct(NumFood, NumPoison) ->
    Foods = [make_object(food) || _ <- lists:seq(1, NumFood)],
    Poisons = [make_object(poison) || _ <- lists:seq(1, NumPoison)],
    Foods ++ Poisons.

make_object(Type) ->
    Radius =
        case Type of
            food -> 1.0 + rand:uniform() * 15.0;
            poison -> 1.0 + rand:uniform() * 20.0
        end,
    #{
        id => make_ref(),
        type => Type,
        pos => {rand:uniform() * 800.0, rand:uniform() * 600.0},
        radius => Radius,
        mass => math:pi() * Radius * Radius
    }.

handle_input(State, Username, Command) ->
    Players = maps:get(players, State),
    case maps:find(Username, Players) of
        error ->
            State;
        {ok, PData} ->
            Mass = maps:get(mass, PData),
            Torque = maps:get(torque, PData),
            Force = maps:get(force, PData),
            Angle = maps:get(angle, PData),
            {Vx, Vy} = maps:get(vel, PData),
            AngVel = maps:get(ang_vel, PData),

            NewPData =
                case Command of
                    left ->
                        AngAcc = Torque / Mass,
                        maps:put(ang_vel, AngVel - AngAcc, PData);
                    right ->
                        AngAcc = Torque / Mass,
                        maps:put(ang_vel, AngVel + AngAcc, PData);
                    forward ->
                        LinAcc = Force / Mass,
                        NewVx = Vx + LinAcc * math:cos(Angle),
                        NewVy = Vy + LinAcc * math:sin(Angle),
                        maps:put(vel, {NewVx, NewVy}, PData);
                    _ ->
                        PData
                end,

            NewPlayers = maps:put(Username, NewPData, Players),
            maps:put(players, NewPlayers, State)
    end.

handle_object_collisions(State) ->
    Players = maps:get(players, State),
    Objects = maps:get(objects, State),
    io:format("Verificando colisões com ~p objetos~n", [length(Objects)]),

    {NewPlayers, NewObjects} = lists:foldl(
        fun(Obj, {PAcc, OAcc}) ->
            {ObjX, ObjY} = maps:get(pos, Obj),
            ObjR = maps:get(radius, Obj),
            ObjM = maps:get(mass, Obj),
            ObjType = maps:get(type, Obj),
            %% verifica colisão com cada jogador
            {NewPAcc, Consumed} = maps:fold(
                fun(Username, PData, {PA, Con}) ->
                    {PX, PY} = maps:get(pos, PData),
                    PR = maps:get(radius, PData),
                    Dist = math:sqrt((PX - ObjX) * (PX - ObjX) + (PY - ObjY) * (PY - ObjY)),

                    case ObjType of
                        poison when Dist < PR ->
                            %% sobreposição com veneno: perde massa
                            MinMass = 250.0,
                            NewMass = max(MinMass, maps:get(mass, PData) - ObjM),

                            NewR = math:sqrt(NewMass / math:pi()),
                            NewPData = PData#{mass => NewMass, radius => NewR},
                            {maps:put(Username, NewPData, PA), true};
                        food when Dist + ObjR =< PR ->
                            io:format("Comida: ~p PR=~p ObjR=~p Dist=~p~n", [Username, PR, ObjR, Dist]),
                            %% captura total: ganha massa
                            NewMass = maps:get(mass, PData) + ObjM,
                            NewR = math:sqrt(NewMass / math:pi()),
                            NewPData = PData#{mass => NewMass, radius => NewR},
                            {maps:put(Username, NewPData, PA), true};
                        _ ->
                            {PA, Con}
                    end
                end,
                {PAcc, false},
                PAcc
            ),

            case Consumed of
                % remove objecto e gera um novo do mesmo tipo
                true ->
                    NewObj = make_object(ObjType),
                    {NewPAcc, [NewObj | OAcc]};
                % mantém objecto
                false -> {NewPAcc, [Obj | OAcc]}
            end
        end,
        {Players, []},
        Objects
    ),

    %% garante pelo menos 1 objecto comestível menor que o menor jogador
    FinalObjects = ensure_min_food(NewPlayers, NewObjects),

    State#{players => NewPlayers, objects => FinalObjects}.

ensure_min_food(Players, Objects) ->
    MinPlayerRadius = lists:min(
        [maps:get(radius, P) || {_, P} <- maps:to_list(Players)]
    ),
    HasSmallFood = lists:any(
        fun(O) -> maps:get(type, O) =:= food andalso maps:get(radius, O) < MinPlayerRadius end,
        Objects
    ),
    case HasSmallFood of
        true ->
            Objects;
        false ->
            %% cria um objecto comestível garantidamente menor
            SmallR = MinPlayerRadius * 0.5,
            NewObj = #{
                id => make_ref(),
                type => food,
                pos => {rand:uniform() * 800.0, rand:uniform() * 600.0},
                radius => SmallR,
                mass => math:pi() * SmallR * SmallR
            },
            [NewObj | Objects]
    end.

handle_player_collisions(State) ->
    PlayersMap = maps:get(players, State),
    UserIDs = maps:keys(PlayersMap),
    
    % Usamos foldl para que cada colisão atualize o "mundo" para o próximo par
    NewPlayersMap = lists:foldl(
        fun(U1, Acc) ->
            % Verificamos se o jogador U1 ainda "existe" no acumulador e não foi comido
            case maps:find(U1, Acc) of
                {ok, P1} -> 
                    % Comparamos P1 com todos os OUTROS jogadores
                    Others = maps:to_list(maps:remove(U1, Acc)),
                    check_all_opponents(U1, P1, Others, Acc);
                error -> Acc
            end
        end,
        PlayersMap,
        UserIDs
    ),
    State#{players => NewPlayersMap}.

check_all_opponents(U1, P1, Others, Acc) ->
    lists:foldl(
        fun({U2, P2}, InnerAcc) ->
            % Pegamos a versão mais atual de P1 (ele pode ter crescido no sub-loop)
            P1_Latest = maps:get(U1, InnerAcc),
            
            {X1, Y1} = maps:get(pos, P1_Latest),
            {X2, Y2} = maps:get(pos, P2),
            R1 = maps:get(radius, P1_Latest),
            R2 = maps:get(radius, P2),
            
            Dist = math:sqrt((X1 - X2)*(X1 - X2) + (Y1 - Y2)*(Y1 - Y2)),
            % Condição: Centro do menor dentro do corpo do maior + margem de tamanho
            Threshold = 1.1,

            if
                (Dist + R2 =< R1) andalso (R1 > R2) ->
                    %% P1 come P2
                    io:format("~s COMEU ~s!~n", [U1, U2]),
                    Mass1 = maps:get(mass, P1_Latest),
                    Mass2 = maps:get(mass, P2),
                    Transfer = Mass2 / 4,
                    NewMass = Mass1 + Transfer,
                    NewR = math:sqrt(NewMass / math:pi()),
                    
                    % Atualiza P1 e dá Respawn no P2
                    Acc1 = maps:put(U1, P1_Latest#{mass => NewMass, radius => NewR, score => maps:get(score, P1_Latest) + 1}, InnerAcc),
                    maps:put(U2, respawn_player(P2), Acc1);
                
                (Dist + R1 =< R2) andalso (R2 > R1) ->
                    %% P2 come P1
                    io:format("~s COMEU ~s!~n", [U2, U1]),
                    Mass1 = maps:get(mass, P1_Latest),
                    Mass2 = maps:get(mass, P2),
                    Transfer = Mass1 / 4,
                    NewMass = Mass2 + Transfer,
                    NewR = math:sqrt(NewMass / math:pi()),
                    
                    % Atualiza P2 e dá Respawn no P1
                    Acc1 = maps:put(U2, P2#{mass => NewMass, radius => NewR, score => maps:get(score, P2) + 1}, InnerAcc),
                    maps:put(U1, respawn_player(P1_Latest), Acc1);
                
                true -> InnerAcc
            end
        end,
        Acc,
        Others
    ).

respawn_player(OldPData) ->
    Mass = 800.0,
    #{
        pos => {rand:uniform() * 800.0, rand:uniform() * 600.0},
        vel => {0.0, 0.0},
        angle => 0.0,
        ang_vel => 0.0,
        mass => Mass,
        torque => 10.00,
        force => 25.00,
        score => maps:get(score, OldPData),
        radius => math:sqrt(Mass / math:pi()),
        pid => maps:get(pid, OldPData) 
    }.



% adaptei o encode_state para o formato que o cliente espera (Nome,x,y,ângulo|Nome...)
encode_state(State) ->
    Players = maps:get(players, State),
    Objects = maps:get(objects, State),

    PlayersList = lists:join(
        "|",
        lists:map(
            fun({Username, PData}) ->
                {X, Y} = maps:get(pos, PData),
                Angle = maps:get(angle, PData),
                Mass = maps:get(mass, PData),
                Score = maps:get(score, PData),
                io_lib:format(
                    "P,~s,~f,~f,~f,~f,~b",
                    [binary_to_list(Username), float(X), float(Y), float(Angle), float(Mass), Score]
                )
            end,
            maps:to_list(Players)
        )
    ),

    Objects_str = lists:join(
        "|",
        lists:map(
            fun(Obj) ->
                {X, Y} = maps:get(pos, Obj),
                Type =
                    case maps:get(type, Obj) of
                        food -> "F";
                        poison -> "V"
                    end,
                Radius = maps:get(radius, Obj),
                io_lib:format("O,~s,~f,~f,~f", [Type, float(X), float(Y), float(Radius)])
            end,
            Objects
        )
    ),
    list_to_binary(PlayersList ++ "|" ++ Objects_str ++ "\n"). 

%renovado a cada tick 
update(State) ->
    State1 = move_players(State),
    State2 = apply_boundaries(State1),
    State3 = handle_object_collisions(State2),
    State4 = handle_player_collisions(State3),
    State4.

move_players(State) ->
    Players = maps:get(players, State),
    NewPlayers = maps:map(
        fun(_Username, PData) ->
            {X, Y} = maps:get(pos, PData),
            {Vx, Vy} = maps:get(vel, PData),
            Angle = maps:get(angle, PData),
            AngVel = maps:get(ang_vel, PData),

            % 1. Atualiza posição e ângulo com a velocidade atual
            NewX = X + Vx,
            NewY = Y + Vy,
            NewAngle = Angle + AngVel,

            % 2. Aplica um amortecimento SUAVE (atrito) à velocidade
            DampedVx = Vx * 0.98,        % linear perde 0.5% por tick
            DampedVy = Vy * 0.98,
            DampedAngVel = AngVel * 0.90, % angular perde 2% por tick

            PData#{
                pos   => {NewX, NewY},
                vel   => {DampedVx, DampedVy},
                angle => NewAngle,
                ang_vel => DampedAngVel
            }
        end,
        Players
    ),
    maps:put(players, NewPlayers, State).

% limites do mapa
apply_boundaries(State) ->
    Players = maps:get(players, State),
    NewPlayers = maps:map(
        fun(_Username, PData) ->
            {X, Y} = maps:get(pos, PData),
            {Vx, Vy} = maps:get(vel, PData),
            {NewX, NewVx} = clamp(X, 0.0, 800.0, Vx),
            {NewY, NewVy} = clamp(Y, 0.0, 600.0, Vy),
            PData#{
                pos => {float(NewX), float(NewY)},
                vel => {float(NewVx), float(NewVy)}
            }
        end,
        Players
    ),
    maps:put(players, NewPlayers, State).

clamp(Val, Min, Max, _Vel) when Val < Min -> {float(Min), 0.0};
clamp(Val, Min, Max, _Vel) when Val > Max -> {float(Max), 0.0};
clamp(Val, _, _, Vel) -> {float(Val), float(Vel)}.

%envia o estado atual do jogo a todos os jogadores
broadcast(State) ->
    Players = maps:get(players, State),
    Json = encode_state(State),
    lists:foreach(
        fun({_Username, Data}) ->
            Pid = maps:get(pid, Data),
            Pid ! {game_update, Json}
        end,
        maps:to_list(Players)
    ).
