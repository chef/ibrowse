%%%-------------------------------------------------------------------
%%% File    : ibrowse_lb.erl
%%% Author  : chandru <chandrashekhar.mullaparthi@t-mobile.co.uk>
%%% Description : 
%%%
%%% Created :  6 Mar 2008 by chandru <chandrashekhar.mullaparthi@t-mobile.co.uk>
%%%-------------------------------------------------------------------
-module(ibrowse_lb).
-author(chandru).
-behaviour(gen_server).
%%--------------------------------------------------------------------
%% Include files
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% External exports
-export([start_link/1,
         spawn_connection/5,
         stop/1,
         get_request_count/1]).

%% API for HTTP connection processes
-export([increment_current/2,
         decrement_current_pipeline/2]).


%% gen_server callbacks
-export([
	 init/1,
	 handle_call/3,
	 handle_cast/2,
	 handle_info/2,
	 terminate/2,
	 code_change/3
	]).

-record(state, {parent_pid,
        active=dict:new(),
		host,
		port,
		max_sessions,
		max_pipeline_size,
		num_cur_sessions = 0,
                proc_state
               }).

-record('EXIT', {from,
                 reason}).

-include("ibrowse.hrl").

%%====================================================================
%% External functions
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link/0
%% Description: Starts the server
%%--------------------------------------------------------------------
start_link(Args) ->
    gen_server:start_link(?MODULE, Args, []).

%%====================================================================
%% Server functions
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init/1
%% Description: Initiates the server
%% Returns: {ok, State}          |
%%          {ok, State, Timeout} |
%%          ignore               |
%%          {stop, Reason}
%%--------------------------------------------------------------------
init([Host, Port]) ->
    process_flag(trap_exit, true),
    Max_sessions = ibrowse:get_config_value({max_sessions, Host, Port}, 10),
    Max_pipe_sz = ibrowse:get_config_value({max_pipeline_size, Host, Port}, 10),
    put(my_trace_flag, ibrowse_lib:get_trace_status(Host, Port)),
    put(ibrowse_trace_token, ["LB: ", Host, $:, integer_to_list(Port)]),
    {ok, #state{parent_pid = whereis(ibrowse),
		host = Host,
		port = Port,
		max_pipeline_size = Max_pipe_sz,
	        max_sessions = Max_sessions}}.

spawn_connection(Lb_pid, Url,
		 Max_sessions,
		 Max_pipeline_size,
		 SSL_options)
  when is_pid(Lb_pid),
       is_record(Url, url),
       is_integer(Max_pipeline_size),
       is_integer(Max_sessions) ->
    gen_server:call(Lb_pid,
		    {spawn_connection, Url, Max_sessions, Max_pipeline_size, SSL_options}).

stop(Lb_pid) ->
    case catch gen_server:call(Lb_pid, stop) of
        {'EXIT', {timeout, _}} ->
            exit(Lb_pid, kill);
        ok ->
            ok
    end.

increment_current(Lb_pid, Req_pid) ->
    gen_server:call(Lb_pid, {increment_current, Req_pid}, infinity).

decrement_current_pipeline(Lb_pid, Req_pid) ->
    gen_server:call(Lb_pid, {decrement_current_pipeline, Req_pid}, infinity).

get_request_count(Lb_pid) ->
    gen_server:call(Lb_pid, get_request_count, infinity).

%%--------------------------------------------------------------------
%% Function: handle_call/3
%% Description: Handling call messages
%% Returns: {reply, Reply, State}          |
%%          {reply, Reply, State, Timeout} |
%%          {noreply, State}               |
%%          {noreply, State, Timeout}      |
%%          {stop, Reason, Reply, State}   | (terminate/2 is called)
%%          {stop, Reason, State}            (terminate/2 is called)
%%--------------------------------------------------------------------

handle_call(get_request_count, _From, #state{active=Active}=State) ->
    {reply, dict:size(Active), State};
handle_call({increment_current, Req_pid}, _From, #state{active=Active}=State) ->
    {Cur_sz, Speculative_sz} = dict:fetch(Req_pid, Active),
    {reply, ok, State#state{active=dict:store(Req_pid, {Cur_sz + 1, Speculative_sz}, Active)}};
handle_call({decrement_current_pipeline, Req_pid}, _From, #state{active=Active}=State) ->
    {Cur_sz, Speculative_sz} = dict:fetch(Req_pid, Active),
    {reply, ok, State#state{active=dict:store(Req_pid, {Cur_sz - 1, Speculative_sz - 1}, Active)}};
handle_call(stop, _From, #state{active=Active} = State) ->
    stop_all_active(Active),
    {stop, normal, ok, State};

handle_call(_, _From, #state{proc_state = shutting_down} = State) ->
    {reply, {error, shutting_down}, State};

%% Update max_sessions in #state with supplied value
handle_call({spawn_connection, _Url, Max_sess, Max_pipe, _}, _From,
	    #state{num_cur_sessions = Num} = State)
    when Num >= Max_sess ->
    find_best_connection(State, Max_sess,  Max_pipe);

handle_call({spawn_connection, Url, Max_sess, Max_pipe, SSL_options}, _From,
	    #state{num_cur_sessions = Cur, active=Active} = State) ->
    {ok, Pid} = ibrowse_http_client:start_link({self(), Url, SSL_options}),
    Active1 = dict:store(Pid, {0, 0}, Active),
    {reply, {ok, Pid}, State#state{num_cur_sessions = Cur + 1,
                                   active=Active1,
                                   max_sessions = Max_sess,
                                   max_pipeline_size = Max_pipe}};

handle_call(Request, _From, State) ->
    Reply = {unknown_request, Request},
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast/2
%% Description: Handling cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info/2
%% Description: Handling all non call/cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%%--------------------------------------------------------------------
handle_info(#'EXIT'{from=Parent}, #state{parent_pid = Parent, active=Active} = State) ->
    stop_all_active(Active),
    {stop, normal, State};

handle_info(#'EXIT'{from=From}, #state{num_cur_sessions=Cur, active=Active}=State) ->
    case dict:erase(From, Active) of
        Active ->
            {noreply, State};
        Active1 ->
            case get(my_trace_flag) of
                true ->
                    Token = get(ibrowse_trace_token),
                    error_logger:info("~s: request process ~p died~n", [Token, From]);
                _ ->
                    ok
            end,
            {noreply, State#state{num_cur_sessions = Cur - 1, active=Active1}}
    end;

handle_info({trace, Bool}, #state{active=Active} = State) when Bool == true;
                                                               Bool == false ->
    F = fun(Pid, _Counters, Acc) -> Pid ! {trace, Bool}, Acc end,
    dict:fold(F, [], Active),
    put(my_trace_flag, Bool),
    {noreply, State};

handle_info(timeout, State) ->
    %% We can't shutdown the process immediately because a request
    %% might be in flight. So we first remove the entry from the
    %% ibrowse_lb ets table, and then shutdown a couple of seconds
    %% later
    ets:delete(ibrowse_lb, {State#state.host, State#state.port}),
    erlang:send_after(2000, self(), shutdown),
    {noreply, State#state{proc_state = shutting_down}};

handle_info(shutdown, State) ->
    {stop, normal, State};

handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: terminate/2
%% Description: Shutdown the server
%% Returns: any (ignored by gen_server)
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% Func: code_change/3
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState}
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------
find_best_connection(#state{active=Active}=State, Max_sess,  Max_pipe) ->
    {Result, Active1} = find_connection(dict:fetch_keys(Active), Active, Max_pipe),
    {reply, Result, State#state{active=Active1,
                                max_sessions = Max_sess,
                                max_pipeline_size = Max_pipe}}.

find_connection([], Active, _) ->
    {{error, retry_later}, Active};
find_connection([Pid|T], Active, Max_pipe) ->
    Counters = {Cur_sz, Speculative_sz} = dict:fetch(Pid, Active),
    case Cur_sz < Max_pipe andalso Speculative_sz < Max_pipe of
        true ->
            {{ok, Pid}, update_speculative_counter(Pid, Counters, Active)};
        false ->
            find_connection(T, Active, Max_pipe)
    end.

update_speculative_counter(Pid, {Cur_sz, Speculative_sz}, Active) when Speculative_sz > 9999999 ->
    dict:store(Pid, {Cur_sz, 1}, Active);
update_speculative_counter(Pid, {Cur_sz, Speculative_sz}, Active) ->
    dict:store(Pid, {Cur_sz, Speculative_sz + 1}, Active).

stop_all_active(Active) ->
    stop_all_active(dict:size(Active), Active).

stop_all_active(0, _Active) ->
    ok;
stop_all_active(_, Active) ->
    F = fun(Pid, _Counts) -> ibrowse_http_client:stop(Pid) end,
    dict:map(F, Active).
