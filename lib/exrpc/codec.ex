defmodule Exrpc.Codec do
  @moduledoc """
  Binary protocol for Exrpc.

  ## Examples

      iex> Exrpc.Codec.encode(:mfa_list)
      "?"
      iex> Exrpc.Codec.decode("?")
      :mfa_list

      iex> bin = Exrpc.Codec.encode([1, [1, 2, 3]])
      <<33, 131, 108, 0, 0, 0, 2, 97, 1, 107, 0, 3, 1, 2, 3, 106>>
      iex> Exrpc.Codec.decode(bin)
      [1, [1, 2, 3]]

      iex> bin = Exrpc.Codec.encode({:goodrpc, "hello"})
      <<2, 131, 109, 0, 0, 0, 5, 104, 101, 108, 108, 111>>
      iex> Exrpc.Codec.decode(bin)
      {:goodrpc, "hello"}

      iex> Exrpc.Codec.encode({:badrpc, :invalid_request})
      <<4>>
      iex> Exrpc.Codec.decode(<<4>>)
      {:badrpc, :invalid_request}

      iex> bin = Exrpc.Codec.encode({:badrpc, %ArgumentError{message: "ugh"}})
      <<5, 131, 116, 0, 0, 0, 3, 119, 7, 109, 101, 115, 115, 97, 103, 101, 109, 0, 0, 0, 3, 117, 103, 104, 119, 10, 95, 95, 115, 116, 114, 117, 99, 116, 95, 95, 119, 20, 69, 108, 105, 120, 105, 114, 46, 65, 114, 103, 117, 109, 101, 110, 116, 69, 114, 114, 111, 114, 119, 13, 95, 95, 101, 120, 99, 101, 112, 116, 105, 111, 110, 95, 95, 119, 4, 116, 114, 117, 101>>
      iex> Exrpc.Codec.decode(bin)
      {:badrpc, %ArgumentError{message: "ugh"}}
  """

  @spec encode(term()) :: binary()
  def encode({:goodrpc, data}), do: <<2>> <> term_to_binary(data)
  def encode({:badrpc, :invalid_request}), do: <<4>>
  def encode({:badrpc, reason}), do: <<5>> <> term_to_binary(reason)
  def encode(:mfa_list), do: "?"

  def encode([fun_id, args] = term) when is_integer(fun_id) and is_list(args),
    do: "!" <> term_to_binary(term)

  @spec decode(binary()) :: term()
  def decode(<<2, bin::binary>>), do: {:goodrpc, binary_to_term(bin)}
  def decode(<<4>>), do: {:badrpc, :invalid_request}
  def decode(<<5, bin::binary>>) do
    case binary_to_term(bin) do
      :decode_error -> :decode_error
      reason -> {:badrpc, reason}
    end
  end

  def decode("?"), do: :mfa_list

  def decode("!" <> bin) do
    with [fun_id, args] when is_integer(fun_id) and is_list(args) <- binary_to_term(bin) do
      [fun_id, args]
    end
  end

  def decode(_), do: :decode_error

  defp term_to_binary(term), do: :erlang.term_to_binary(term)

  defp binary_to_term(bin) do
    Plug.Crypto.non_executable_binary_to_term(bin)
  rescue
    ArgumentError ->
      :decode_error
  end
end
