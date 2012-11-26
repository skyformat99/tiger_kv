%%%-------------------------------------------------------------------
%%% @author  <yaoxinming@gmail.com>
%%% @copyright (C) 2012, 
%%% @doc
%%%
%%% @end
%%% Created : 26 Nov 2012 by  <>
%%%-------------------------------------------------------------------
-module(redis_frontend).

-behaviour(gen_server).

%% API
-export([start_link/4]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-define(SERVER, ?MODULE). 

-record(state, {parser_state,socket}).
-include("tiger_kv_main.hrl").

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------

start_link (_ListenPid,Socket,Transport,TransOps) ->
    gen_server:start_link( ?MODULE, [Socket,Transport,TransOps],[]).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([Socket,_,_]) ->
    inet:setopts(Socket,[binary,
			       {packet, raw},
			       {active, once},
			       {reuseaddr, true},
			       {nodelay, true},
			       {keepalive, true}]),
    {ok, #state{socket=Socket,parser_state=#pstate{}}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info({tcp, Socket, Bin}, #state{socket = Socket,parser_state=ParserState
				      } = StateData) ->
    Result=case redis_parser:parse(ParserState,Bin) of
	       {ok,Req,NewParserState}->
		   Rep=process_req(Req,Socket),
		   gen_tcp:send(Socket,Rep),
		   ok = inet:setopts(Socket, [{active, once}]),
		   StateData#state{parser_state=NewParserState};
	       {ok,Req,_Rest,NewParserState}->
		   Rep=process_req(Req,Socket),
		   gen_tcp:send(Socket,Rep),
		   ok = inet:setopts(Socket, [{active, once}]),
		   StateData#state{parser_state=NewParserState};
	       {continue,NewParserState}->
		   StateData#state{parser_state=NewParserState}
	   end,
    {noreply,Result};
handle_info({tcp_closed, Socket},  #state{socket = Socket
                                                     } = StateData) ->

  {stop, normal, StateData};
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
process_req([<<"SET">>,K,V],_Socket)->
    Rep=case redis_backend:put(K,V) of
	    ok->
		<<"+OK",?NL>>;
	    {error,not_ready}->
		<<"-not_ready",?NL>>;
	    _ ->
		<<"-error",?NL>>
	end,
    Rep;
process_req([<<"GET">>,K],_Socket) ->
    Rep=case redis_backend:get(K) of
	    {ok,Value}->
		Size=erlang:size(Value),
		S=list_to_binary(erlang:integer_to_list(Size)),
		<<"$",S/binary,?NL,Value/binary,?NL>>
		;
	    not_found->
		<<"$-1",?NL>>;
	    _ ->
		<<"-error",?NL>>
	end,
    Rep;
process_req([<<"DEL">>,K],_Socket) ->
    Rep=case redis_backend:delete(K) of
	    ok->
		<<"+OK",?NL>>;	    
	    _ ->
		<<"-error",?NL>>
	end,
    Rep;
process_req(<<"SELECT",_Rest/binary>>,_Socket) ->
    <<"+OK",?NL>>;
process_req(_A,_Socket) ->
    <<"-error_not_support",?NL>>.

	
