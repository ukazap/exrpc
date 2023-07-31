defmodule Exrpc.Server.Handler do
  @moduledoc false
  use ThousandIsland.Handler

  alias Exrpc.Request
  alias Exrpc.Response
  alias Redix.Protocol, as: RESP
  alias ThousandIsland.Socket

  defmodule State do
    @moduledoc false
    @enforce_keys [:mfa_lookup]
    defstruct [:mfa_lookup, :resp_continuation]
  end

  @impl ThousandIsland.Handler
  def handle_connection(socket, state), do: serve(socket, state)

  # Socket recv and RESP parsing loop

  defp serve(socket, %State{resp_continuation: nil} = state) do
    case Socket.recv(socket) do
      {:error, _} -> {:close, state}
      {:ok, data} -> handle_parse(RESP.parse(data), socket, state)
    end
  end

  defp serve(socket, %State{resp_continuation: fun} = state) do
    case Socket.recv(socket) do
      {:error, _} -> {:close, state}
      {:ok, data} -> handle_parse(fun.(data), socket, state)
    end
  end

  defp handle_parse({:continuation, fun}, socket, state) do
    serve(socket, %State{state | resp_continuation: fun})
  end

  defp handle_parse({:ok, request, left_over}, socket, state) do
    case handle_and_respond(request, socket, state.mfa_lookup) do
      {:error, _reason} ->
        {:close, state}

      :ok ->
        case left_over do
          "" -> serve(socket, %State{state | resp_continuation: nil})
          _ -> handle_parse(RESP.parse(left_over), socket, state)
        end
    end
  end

  # Request handling and responding

  defp handle_and_respond(request, socket, mfa_lookup) do
    request
    |> Request.decode()
    |> handle_request(mfa_lookup)
    |> maybe_send_response(socket)
  end

  defp handle_request(:ping, _) do
    :pong
  end

  defp handle_request(:list, mfa_lookup) do
    case Exrpc.MFALookup.to_list(mfa_lookup) do
      list when is_list(list) -> {:goodrpc, list}
      error -> error
    end
  end

  defp handle_request({:apply, id, arg}, mfa_lookup) do
    arity = length(arg)

    case Exrpc.MFALookup.id_to_mfa(mfa_lookup, id) do
      {:error, :invalid_mfa_lookup} = error ->
        error

      {mod, fun, ^arity} ->
        try do
          result = apply(mod, fun, arg)
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

  defp handle_request(_, _) do
    {:badrpc, :invalid_request}
  end

  defp maybe_send_response({:error, :invalid_mfa_lookup} = error, _), do: error
  defp maybe_send_response(response, socket) do
    encoded = Response.encode(response)
    Socket.send(socket, encoded)
  end
end
