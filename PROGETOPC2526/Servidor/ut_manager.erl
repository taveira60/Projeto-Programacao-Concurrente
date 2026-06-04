

-module(ut_manager).
-export([start/0]).

start() ->
    spawn(fun() -> loop(#{}, #{}) end).


loop(Users, Logged) ->
    receive
        %% Criar conta
        {register_usr, From, Username, Password} ->
            case maps:is_key(Username, Users) of
                true ->
                    From ! {error, user_exists},
                    loop(Users, Logged);
                false ->
                    NewUsers = maps:put(Username, Password, Users),
                    From ! {ok, registered, Username},
                    loop(NewUsers, Logged)
            end;
        %% Utilizador faz login
        {login_usr, From, Username, Password} ->
            case maps:find(Username, Users) of
                error ->
                    From ! {error, user_not_found},
                    loop(Users, Logged);
                {ok, StoredPass} ->
                    case StoredPass =:= Password of
                        false ->
                            From ! {error, wrong_password},
                            loop(Users, Logged);
                        true ->
                            case maps:is_key(Username, Logged) of
                                true ->
                                    From ! {error, already_logged},
                                    loop(Users, Logged);
                                false ->
                                    NewLogged = maps:put(Username, true, Logged),
                                    From ! {ok, logged, Username},
                                    loop(Users, NewLogged)
                            end
                    end
            end;
        %% cancelar o registo 
        {unregister_usr, From, Username, Password} ->
            case maps:find(Username, Users) of
                error ->
                    From ! {error, user_not_found},
                    loop(Users, Logged);
                {ok, StoredPass} ->
                    case StoredPass =:= Password of
                        true ->
                            NewUsers = maps:remove(Username, Users),  
                            NewLogged = maps:remove(Username, Logged),
                            From ! ok,
                            loop(NewUsers, NewLogged);
                        false ->
                            From ! {error, wrong_password},
                            loop(Users, Logged)
                    end
            end;
        {logout_usr, From, Username} ->
            case maps:is_key(Username, Logged) of
                true ->
                    NewLogged = maps:remove(Username, Logged),
                    From ! {ok, logged_out},
                    loop(Users, NewLogged);
                false ->
                    From ! {error, not_logged},
                    loop(Users, Logged)
            end
    end.