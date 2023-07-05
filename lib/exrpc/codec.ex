defmodule Exrpc.Codec do
  @moduledoc false

  @spec encode(term()) :: binary()
  def encode(term), do: :erlang.term_to_binary(term)

  @spec decode(binary()) :: term() | :decode_error
  def decode(bin) do
    {:ok, Plug.Crypto.non_executable_binary_to_term(bin, [:safe])}
  rescue
    ArgumentError ->
      :decode_error
  end
end
