-module(client_handler).
-export([init/4]).   % agora são 4 argumentos

init(Socket, UTM, MM, TopM) ->
    login_loop(Socket, UTM, MM, TopM).

join_queue(MATCHMAKER_PID,Username) ->  % PID: MATCHMAKER_PID
    MATCHMAKER_PID ! {join_queue, self(),Username}.

leave_queue(M_Pid, Username) ->
    M_Pid ! {leave_queue, self(), Username}.
    

login_loop(Socket, UTM, MM, TopM) -> %aqui eu vou receber algo no formato {tcp,Socket,Data}
    receive 
        {tcp,Socket,Data} -> % RECEBI ALGO DO JAVA (user_input)
        Data1 = strip_newline(Data), %tira o /n no final 
        Lista = binary:split(Data1, <<":">>, [global]), 
        case Lista of %caso for um pedido do java isto vem no formato acima
            [<<"LOGIN">>, Username, Pass] -> 
                UTM ! {login_usr, self(), Username, Pass},
                login_loop(Socket, UTM, MM, TopM);
            [<<"REGIST">>, Username, Pass] -> 
                UTM ! {register_usr, self(), Username, Pass},
                login_loop(Socket, UTM, MM, TopM);
            [<<"UNREGIST">>, Username, Pass] -> 
                UTM ! {unregister_usr, self(), Username, Pass},
                login_loop(Socket, UTM, MM, TopM);
            [<<"LOGOUT">>, Username] ->
                UTM ! {logout_usr, self(), Username},
                login_loop(Socket, UTM, MM, TopM);
            _ ->
                gen_tcp:send(Socket, <<"(ERROR) COMANDO_INVALIDO\n">>),
                login_loop(Socket, UTM, MM, TopM)
            end;
        
        {ok, registered, _Username}->
            gen_tcp:send(Socket, <<"<REGISTRADO>\n">>),
            login_loop(Socket, UTM, MM, TopM);
            
        {ok,logged, Username} -> % sai do loop!!! entra no matchmaker
            gen_tcp:send(Socket, <<"<ENTRASTE>\n">>),
            matchmaker_loop(Socket, UTM, MM, Username, TopM);
            

        {error, already_logged} ->
            gen_tcp:send(Socket, <<"(ERROR) JA ESTAS LOGADO!\n">>),
            login_loop(Socket, UTM, MM, TopM);
        
            
        {error, wrong_password} ->
            gen_tcp:send(Socket, <<"(ERROR) PASSWORD ERRADA!\n">>),
            login_loop(Socket, UTM, MM, TopM);
        
        
        {error, user_exists} ->
            gen_tcp:send(Socket, <<"(ERROR) USER JA EXISTE TENTA OUTRA VEZ\n">>),
            login_loop(Socket, UTM, MM, TopM);
        
        {error, user_not_found} ->
            gen_tcp:send(Socket, <<"(ERROR) USER NAO EXISTE\n">>),
            login_loop(Socket, UTM, MM, TopM);
        
        {tcp_closed, Socket} ->
            io:format("Cliente desligou-se durante o login.~n")
        end.

matchmaker_loop(Socket, UTM, MM, Username, TopM) ->
    TopM ! {get_top, self()},
    receive 
        {top, List} -> 
            TopString = encode_top_to_string(List),
            gen_tcp:send(Socket, TopString)
    end,
    receive
        {tcp,Socket,Data} -> 
            Data1 = strip_newline(Data),
            io:format("DEBUG matchmaker recebeu: ~p~n", [Data1]), 
            Lista = binary:split(Data1, <<":">>, [global]), 
            case Lista of %caso for um pedido do java isto vem no formato acima
            [<<"JOIN">>] -> 
                join_queue(MM,Username),
                matchmaker_loop(Socket, UTM, MM, Username, TopM);
            [<<"EXIT">>] ->
                leave_queue(MM,Username),
                matchmaker_loop(Socket, UTM, MM, Username, TopM);
            _ ->
                gen_tcp:send(Socket, <<"(ERROR) COMANDO_INVALIDO\n">>),
                matchmaker_loop(Socket, UTM, MM, Username, TopM)
            end;

        {matchmaker, {game_start, GamePid}} ->
            gen_tcp:send(Socket, <<"GAME_START\n">>), % pus isto aqui para ir para o ecra de jogo tipo depois de esperar
            game_loop(Socket, UTM, MM, Username, GamePid, TopM);
            
        {tcp_closed, Socket} ->
            leave_queue(MM,Username),
            io:format("Cliente desligou-se durante o matchmaking.~n")
        

    end.   

game_loop(Socket, UTM, MM, Username, GamePid, TopM) ->
    receive
        % Agora o que o jogador prime é enviado para o game_session
        {tcp, Socket, Data} ->
            Data1 = strip_newline(Data),
            io:format("DEBUG game_loop recebeu: ~p~n", [Data1]), % simlesmente para debug
            Command = parse_movement(Data1),                       % converte binário para átomo (left, right, forward)
            game_session:send_input(GamePid, Username, Command),  % envia ao processo do jogo
            game_loop(Socket, UTM, MM, Username, GamePid, TopM);

        {exit} ->
            matchmaker_loop(Socket, UTM, MM, Username, TopM);

        {game_update, Json} ->
            gen_tcp:send(Socket, Json),
            game_loop(Socket, UTM, MM, Username, GamePid, TopM);

        
        % Quando o game_session envia {game_over, ...}, voltamos ao matchmaker
        {game_over, _GamePid} ->
            gen_tcp:send(Socket, <<"GAME_OVER\n">>), % adicionei isto que faz com que o cliente saiba que o jogo acabou
            matchmaker_loop(Socket, UTM, MM, Username, TopM);

        {tcp_closed, Socket} ->
            io:format("Cliente desligou-se durante o jogo.~n")
    end.

% Converte os comandos em binário que vêm do cliente (ex: <<"LEFT">>) nos átomos
% que o game_session espera (left, right, forward)
parse_movement(<<"LEFT">>)    -> left;
parse_movement(<<"RIGHT">>)   -> right;
parse_movement(<<"FORWARD">>) -> forward;
parse_movement(_)             -> unknown.


            
            

% funcao auxiliar que remove os /n no final se tiver

strip_newline(Bin) ->
    case binary:last(Bin) of
        $\n -> binary:part(Bin, 0, byte_size(Bin)-1);
        _   -> Bin
    end.

encode_top_to_string(TopList) ->
    % Transforma cada tuplo {Name, Score} numa string "Name,Score"
    Items = lists:map(fun({Name, Score}) ->
        [Name, ",", integer_to_list(Score)]
    end, TopList),
    
    % Junta todos os jogadores com ";" e adiciona a nova linha no fim
    TopString = lists:join($;, Items),
    list_to_binary(["(TOP)",TopString, "\n"]).


