defmodule NojsChat do
  @moduledoc """
  Documentation for `NojsChat`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> NojsChat.hello()
      :world

  """

  def start do
    #dispatch = :cowboy_router.compile( _: [{"/", MyLoopHandler, []}])
    #:cowboy.start_clear(:mything, [port: 4000], %{env: %{dispatch: dispatch}})
    {:ok, roomserver} = GenServer.start_link(RoomServer, ["lol"], name: :roomserver)
    Plug.Cowboy.http(MyRouter, [protocol_options: [idle_timeout: :infinity]])
  end

end

defmodule MyLoopHandler do
  require Logger
  def init(req, _opts) do
    Logger.debug "Loop::init/2"
    :cowboy_req.reply(200, %{"content-type" => "text/html", "connection" => "keep-alive", "refresh" => "55"},
      "<!doctype HTML>\n<html><head><meta http-equiv=\"refresh\" content=\"30\" /><title>streaming</title></head></body>", req)
    #req = :cowboy_req.stream_body(["<!doctype HTML>\n<html><head><title>streaming</title></head>"],:nofin, req)
    #req = :cowboy_req.stream_body(["<body>"], :fin, req)
    {:ok, state} = :timer.send_interval(500, {:doomajiggy, "<p>omg</p>"})
    #:timer.send_after(10000, :stop)
    {:cowboy_loop, req, state}
    #req = :cowboy_req.reply(200, %{"content-type" => "text-plain"}, "Hello, Erlang.", req)
    #{:ok, req, []}
  end

  def info({:doomajiggy, thing}, req, state) do
    Logger.debug "Loop::info/2"
    :cowboy_req.reply(200, %{"content-type" => "text/html", "connection" => "keep-alive", "refresh" => "55"}, "<!doctype HTML>\n<html><head><title>streaming</title></head></body>", req)
    {:ok, req, state, :hibernate}
  end
  def info(:stop, req, state) do
    Logger.debug "Loop::info/2"
    req = :cowboy_req.stream_body("</body></html>", :fin, req)
    {:stop, req, state}
  end
  def info(_msg, req, state) do
    Logger.debug "Loop::info/2"
    {:ok, req, state, :hibernate}
  end

  def terminate(reason, req, state) do
    Logger.debug "Loop::terminate/2"
    Logger.debug (inspect {reason, req, state})
    :timer.cancel(state)
    :ok
  end

end

defmodule MyPlug do
  def init([]) do
    []
  end

  def call(conn, []) do
    {:ok, log} = GenServer.call(:roomserver, {:register, self()})
    header_chunk = """
    <!doctype HTML>
    <html>
    <head>
    <title>Stream</title>
    </head>
    <body style="display: flex; flex-direction: column-reverse;">
    <div>
    """
    history_chunk = Enum.map(log, fn {pid, msg} ->
        chunk = "<p><b>#{String.slice(inspect(pid), 5, 6)}:</b> #{msg}</p>"
    end)

    {:ok, conn} =
      conn
      |> Plug.Conn.put_resp_header("refresh", "55")
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_chunked(200)
      |> Plug.Conn.chunk([header_chunk, history_chunk])

    loop(conn)
    GenServer.call(:roomserver, {:unregister, self()})
  end
  def loop(conn) do
    receive do
      {:update, _room_name, pid, msg} ->
        chunk = "<p><b>#{String.slice(inspect(pid), 5, 6)}:</b> #{msg}</p>"
        case Plug.Conn.chunk(conn, chunk) do
          {:ok, conn} ->
            loop(conn)
          {:error, :closed} ->
            conn
        end
    after
      60000 -> conn
    end
  end
end

defmodule RoomServer do
  require Logger
  def init([name]) do
    Logger.debug "init Room"
    {:ok, %{name: name, log: [], users: []}}
  end
  def handle_call({:register, pid}, _from, state) do
    Logger.debug "register"
    {:reply, {:ok, state.log}, %{state| users: [pid | state.users]}}
  end
  def handle_call({:unregister, pid}, _from, state) do
    Logger.debug "unregister"
    {:reply, :ok, %{state| users: List.delete(state.users, pid)}}
  end
  def handle_call({:send, pid, msg}, _from, state) do
    Logger.debug "send"
    Enum.each(state.users, fn (user_pid) ->
      Process.send(user_pid, {:update, state.name, pid, msg}, [])
    end)
    {:reply, :ok, %{state| log: state.log ++ [{pid, msg}]}}
  end
end

defmodule MyRouter do
  use Plug.Router

  plug Plug.Parsers, [parsers: [:urlencoded, :multipart]]
  plug :match
  plug :dispatch


  get "/" do
    room = "lol"
    lobby = """
    <!doctype HTML>
    <html>
    <head><title>Lobby</title></head>
    <body>
    <h1> Select a Room!</h1>
    <ul>
    <li><a href="/room/#{room}">#{room}</a></li>
    </ul>
    <p> I guess some stuff goes here </p>
    </body>
    </html>
    """
    send_resp(conn, 200, lobby)
  end

  get "/room/:room/stream", to: MyPlug

  post "/room/:room/stream" do
    GenServer.call(:roomserver, {:send, self(), conn.body_params["message"]})
    MyPlug.call(conn, [])
  end

  get "/room/:room" do
    a = """
    <!doctype HTML>
    <html>
    <head><title>Room #{room}</title></head>
    <body>
    <h1> Room #{room} </h1>
    <iframe name="stream" src="/room/#{room}/stream"></iframe>
    <form name="sendform" method="POST" action="/room/#{room}/stream" target="stream">
    <input name="message" type="text" />
    <input value="Send" type="submit" />
    </form>
    <p> Be nice pls </p>
    </body>
    </html>
    """
    send_resp(conn, 200, a)
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end

end
