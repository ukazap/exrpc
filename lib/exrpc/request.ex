defmodule Exrpc.Request do
  @moduledoc false

  @doc "Encode request as Redis command."
  @spec encode(term()) :: list(binary())
  def encode(:list) do
    ["L"]
  end

  def encode({:apply, id, arg}) when is_list(arg) do
    ["X", id, :erlang.term_to_binary(arg)]
  end

  @doc "Decode request from Redis command."
  def decode([head | tail]) do
    do_decode([String.upcase(head) | tail])
  end

  defp do_decode(["L"]) do
    :list
  end

  defp do_decode(["X", id_bin, arg_bin]) do
    case Plug.Crypto.non_executable_binary_to_term(arg_bin) do
      [_ | _] = arg -> {:apply, String.to_integer(id_bin), arg}
      _ -> :invalid_request
    end
  rescue
    Argument -> :invalid_request
  end

  defp do_decode(["PING" | _]) do
    :ping
  end

  defp do_decode(_) do
    :invalid_request
  end
end
