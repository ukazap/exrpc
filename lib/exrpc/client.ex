defmodule Exrpc.Client do
  @moduledoc false

  @behaviour NimblePool

  require Logger

  alias Exrpc.Codec
  alias Exrpc.MFALookup

  @opts [
    packet: :raw,
    mode: :binary,
    active: false,
    keepalive: true
  ]

  @connect_timeout 30_000

  @type t :: pid() | atom()

  def start_link(opts) do
    {host, opts} = Keyword.pop!(opts, :host)
    {port, opts} = Keyword.pop!(opts, :port)

    opts =
      Keyword.merge(opts,
        worker: {__MODULE__, %{server: {to_charlist(host), port, @opts}}},
        pool_size: Keyword.get(opts, :pool_size, 10)
      )

    NimblePool.start_link(opts)
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, name: Keyword.fetch!(opts, :name)},
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @spec mfa_list(t()) :: list(mfa())
  def mfa_list(client_pool) do
    NimblePool.checkout!(client_pool, :checkout, fn _from, {_socket, mfa_lookup} ->
      {MFALookup.to_list(mfa_lookup), :ok}
    end)
  end

  @spec call(t(), module(), atom(), list(), integer() | atom()) ::
          {:badrpc, atom} | {:badrpc, atom, binary} | any()
  def call(client_pool, m, f, a, timeout \\ :infinity)
      when is_atom(m) and is_atom(f) and is_list(a) do
    NimblePool.checkout!(client_pool, :checkout, fn _from, {socket, mfa_lookup} ->
      with socket when is_port(socket) <- socket,
           id when is_integer(id) <-
             MFALookup.mfa_to_id(mfa_lookup, {m, f, length(a)}),
           message <- "!" <> :erlang.term_to_binary([id, a]),
           :ok <- :gen_tcp.send(socket, message),
           {:ok, bin} <- :gen_tcp.recv(socket, 0, timeout) do
        {wrap_response(bin), :ok}
      else
        # tcp issues
        {:error, :closed} = error -> {{:badrpc, :disconnected}, error}
        {:error, :econnrefused} = error -> {{:badrpc, :disconnected}, error}
        {:error, :econnreset} = error -> {{:badrpc, :disconnected}, error}
        {:error, :enotconn} = error -> {{:badrpc, :disconnected}, error}

        # mfa list was not fetched successfully
        {:error, :invalid_mfa_lookup} -> {{:badrpc, :mfa_lookup_fail}, :ok}

        # apply error
        {:error, error} -> {{:badrpc, error}, :ok}
        {:badrpc, error} -> {{:badrpc, error}, :ok}

        # invalid mfa
        nil -> {{:badrpc, :invalid_request}, :ok}
      end
    end)
  end

  defp wrap_response(bin) do
    case Codec.decode(bin) do
      :decode_error -> {:badrpc, :invalid_response, bin}
      {:badrpc, reason} -> {:badrpc, reason}
      {:goodrpc, result} -> result
    end
  end

  @impl NimblePool
  def init_pool(pool_state) do
    {:ok, Map.put(pool_state, :mfa_lookup, nil)}
  end

  @impl NimblePool
  def init_worker(%{server: {host, port, tcp_options}} = pool_state) do
    parent = self()

    async_fn = fn ->
      with {:ok, socket} <- :gen_tcp.connect(host, port, tcp_options, @connect_timeout),
           :ok <- :gen_tcp.controlling_process(socket, parent) do
        socket
      end
    end

    {:async, async_fn, pool_state}
  end

  @impl NimblePool
  def handle_checkout(:checkout, _from, socket, %{mfa_lookup: nil} = pool_state)
      when is_port(socket) do
    mfa_list = fetch_mfa_list(socket)

    case MFALookup.create(mfa_list) do
      {:ok, mfa_lookup} ->
        {:ok, {socket, mfa_lookup}, socket, %{pool_state | mfa_lookup: mfa_lookup}}

      {:error, :empty_list} ->
        {:ok, {socket, nil}, socket, pool_state}
    end
  end

  def handle_checkout(:checkout, _from, socket, pool_state) do
    {:ok, {socket, pool_state.mfa_lookup}, socket, pool_state}
  end

  @impl NimblePool
  def handle_checkin(:ok, _from, socket, pool_state) do
    {:ok, socket, pool_state}
  end

  def handle_checkin({:error, reason}, _from, _socket, pool_state) do
    {:remove, reason, pool_state}
  end

  defp fetch_mfa_list(socket) do
    with :ok <- :gen_tcp.send(socket, Codec.encode(:mfa_list)),
         {:ok, bin} = :gen_tcp.recv(socket, 0),
         {:goodrpc, mfa_list} <- Codec.decode(bin) do
      mfa_list
    else
      _error -> []
    end
  end
end
