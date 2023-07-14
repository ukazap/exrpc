defmodule Exrpc do
  @moduledoc """
  Lean Elixir RPC library based on RESP (REdis Serialization Protocol).

  To set up, start `Exrpc.Server` on the server side and `Exrpc.Client` on the client side.

  ## Server-side

  ```elixir
  # module with function to be called remotely
  defmodule ServerSideModule do
    def hello(name), do: "Hello " <> name
  end

  # start link or add child spec to your supervisor
  Exrpc.Server.start_link(name: HelloRpc, port: 7379, mfa_list: [&ServerSideModule.hello/1])
  ```

  ## Client-side

  ```elixir
  # start link or add child spec to your supervisor
  Exrpc.Client.start_link(name: HelloRpc, host: "localhost", port: 7379)

  # make a remote function call:
  Exrpc.call(HelloRpc, ServerSideModule, :hello, ["world"])
  ```
  """

  require Logger

  alias Exrpc.Client
  alias Exrpc.MFALookup
  alias Exrpc.Request
  alias Exrpc.Response

  @type on_call :: {:badrpc, atom} | {:badrpc, atom, binary} | any()

  @initial_backoff_ms 100
  @max_backoff_ms 5000
  @jitter_factor 0.2

  @doc """
  List available remote functions.

  ## Example

      iex> Exrpc.mfa_list(:my_client)
      [{ServerSideModule, :hello, 1}]
  """
  @spec mfa_list(Client.t()) :: list(mfa())
  def mfa_list(client) do
    Client.InfoTable.get(client, :mfa_list, [])
  end

  @doc """
  Calls a remote function.

  ## Example

      iex> Exrpc.call(:my_client, ServerSideModule, :hello, ["world"])
      "Hello world"
  """
  @spec call(Client.t(), module(), atom(), list(), timeout()) :: on_call()
  def call(client, mod, fun, arg, timeout \\ 5000)
      when is_atom(mod) and is_atom(fun) and is_list(arg) do
    task =
      client
      |> Client.task_via()
      |> Task.Supervisor.async(__MODULE__, :loop_call, [client, mod, fun, arg])

    try do
      Task.await(task, timeout)
    catch
      :exit, {:timeout, _} ->
        Task.shutdown(task, :brutal_kill)
        {:badrpc, :timeout}
    end
  end

  @doc false
  def loop_call(client, mod, fun, arg, retries \\ 0) do
    delay_ms = calculate_delay_ms(retries)
    :timer.sleep(delay_ms)

    with {_, _} = mfa_lookup <- Client.InfoTable.get(client, :mfa_lookup, :mfa_lookup_fail),
         id when is_integer(id) <- MFALookup.mfa_to_id(mfa_lookup, {mod, fun, length(arg)}),
         command <- Request.encode({:apply, id, arg}),
         {:ok, response} <- Redix.command(Client.via(client, retries), command),
         {:goodrpc, result} <- Response.decode(response) do
      result
    else
      :mfa_lookup_fail ->
        loop_call(client, mod, fun, arg, retries + 1)

      nil ->
        {:badrpc, :invalid_request}

      {:error, %Redix.ConnectionError{}} ->
        loop_call(client, mod, fun, arg, retries + 1)

      {:error, %Redix.Error{message: ""}} ->
        {:badrpc, :invalid_request}

      {:badrpc, reason} ->
        {:badrpc, reason}

      {:badrpc, reason, message} ->
        {:badrpc, reason, message}
    end
  end

  defp calculate_delay_ms(0), do: 0

  defp calculate_delay_ms(retries) do
    backoff = retries * @initial_backoff_ms
    capped_backoff = min(@max_backoff_ms, backoff)
    jitter = :rand.uniform() * (capped_backoff * @jitter_factor)
    trunc(capped_backoff + jitter)
  end
end
