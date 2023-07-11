defmodule Exrpc do
  @moduledoc """
  Simple Elixir RPC without Erlang distribution.

  To set up, you need to start `Exrpc.Server` on the server side and `Exrpc.Client` on the client side.

  Start `Exrpc.Server` with a list of modules and functions you want to expose:

  ```elixir
  defmodule ServerSideModule do
    def hello(name), do: "Hello " <> name
  end

  # start link or add child spec to your supervisor
  Exrpc.Server.start_link(name: :my_server, port: 5670, mfa_list: [&ServerSideModule.hello/1])
  ```

  Start `Exrpc.Client` with the address of the server:

  ```elixir
  # start link or add child spec to your supervisor
  Exrpc.Client.start_link(name: :my_client, host: "localhost", port: 5670)
  ```
  """

  @doc """
  List available remote functions.

      iex> Exrpc.mfa_list(:my_client)
      [{ServerSideModule, :hello, 1}]
  """
  @spec mfa_list(Exrpc.Client.t()) :: list(mfa())
  defdelegate mfa_list(client), to: Exrpc.Client

  @doc """
  Calls a remote function.

      iex> Exrpc.call(:my_client, ServerSideModule, :hello, ["world"])
      "Hello world"
  """
  @spec call(Exrpc.Client.t(), module(), atom(), list()) ::
          {:badrpc, atom} | {:badrpc, atom, binary} | any()
  @spec call(Exrpc.Client.t(), module(), atom(), list(), timeout()) ::
          {:badrpc, atom} | {:badrpc, atom, binary} | any()
  # defdelegate call(client, mod, fun, args, timeout \\ :infinity), to: Exrpc.Client


  def call(client, mod, fun, args, timeout \\ :infinity) do
    parent = self()

    try do
      Task.async(Exrpc.Client, :call, [client, mod, fun, args, timeout])
      |> Task.await(timeout)
    catch
      :exit, {:timeout, {Task, :await, [%Task{mfa: {Exrpc.Client, :call, 5}, owner: ^parent}, _]}} ->
        {:badrpc, :timeout}
      :exit, {:timeout, {NimblePool, :checkout, [^client]}} ->
        {:badrpc, :timeout}
    end
  end
end
