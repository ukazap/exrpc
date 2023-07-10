defmodule Exrpc.Server.Handler do
  @moduledoc false

  use ThousandIsland.Handler

  alias Exrpc.Codec
  alias Exrpc.MFALookup

  @impl ThousandIsland.Handler
  def handle_data(data, socket, mfa_lookup) do
    reply =
      data
      |> Codec.decode()
      |> process(mfa_lookup)
      |> Codec.encode()

    ThousandIsland.Socket.send(socket, reply)
    {:continue, mfa_lookup}
  end

  defp process(:mfa_list, mfa_lookup) do
    {:goodrpc, MFALookup.to_list(mfa_lookup)}
  end

  defp process([id, args], mfa_lookup) when is_list(args) do
    arity = length(args)

    case MFALookup.id_to_mfa(mfa_lookup, id) do
      {mod, fun, ^arity} ->
        try do
          result = apply(mod, fun, args)
          {:goodrpc, result}
        rescue
          exception -> {:badrpc, exception}
        catch
          thrown -> {:badrpc, thrown}
        end

      _ ->
        {:badrpc, :invalid_request}
    end
  end

  defp process(_, _) do
    {:badrpc, :invalid_request}
  end
end
