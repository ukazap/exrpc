defmodule Exrpc do
  @moduledoc "Elixir RPC without Erlang distribution"

  @spec mfa_list(Exrpc.Client.t()) :: list(mfa())
  defdelegate mfa_list(client_pool), to: Exrpc.Client

  @spec call(Exrpc.Client.t(), module(), atom(), list(), timeout()) ::
          {:badrpc, atom} | {:badrpc, atom, binary} | any()
  defdelegate call(client_pool, mod, fun, args, timeout \\ :infinity), to: Exrpc.Client
end
