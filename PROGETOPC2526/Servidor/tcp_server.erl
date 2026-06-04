-module(tcp_server).
-export([start/1]).

start(Port) ->
    % Inicia os gestores globais
    TopM = top_manager:start(),
    UTM = ut_manager:start(), %% user manager trata dos logins 
    MM  = matchmaker:start(TopM),  %% matchmaker 
    
    % Abre o Socket TCP (se houver tempo seria o ideal trocar para {active, once})
    {ok, LSocket} = gen_tcp:listen(Port, [binary, {packet, line}, {active, true}, {reuseaddr, true}]),
    io:format("Servidor ON na porta ~p~n", [Port]),
    acceptor(LSocket, UTM, MM, TopM).

acceptor(LSocket, UTM, MM, TopM) ->
    {ok, Socket} = gen_tcp:accept(LSocket),
    % Cria um handler para o novo jogador
    spawn(fun() -> acceptor(LSocket, UTM, MM, TopM) end),   
    client_handler:init(Socket, UTM, MM, TopM).              