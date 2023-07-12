defmodule Exrpc.Response do
  @moduledoc false

  @delimiter "\r\n"

  @doc "Encode messages to inner binary and pack it in RESP."
  @spec encode(term()) :: binary()
  def encode(:pong) do
    "+" <> "PONG" <> @delimiter
  end

  def encode({:badrpc, :invalid_request}) do
    "-" <> @delimiter
  end

  def encode({:badrpc, reason}) do
    bin = <<1>> <> :erlang.term_to_binary(reason)
    "$" <> Integer.to_string(byte_size(bin)) <> @delimiter <> bin <> @delimiter
  end

  def encode({:goodrpc, result}) do
    bin = <<0>> <> :erlang.term_to_binary(result)
    "$" <> Integer.to_string(byte_size(bin)) <> @delimiter <> bin <> @delimiter
  end

  @doc "Decode message from inner binary (RESP already unpacked)."
  @spec decode(binary()) :: {:badrpc, :invalid_response, binary()} | term()
  def decode(<<1>> <> rest) do
    {:badrpc, Plug.Crypto.non_executable_binary_to_term(rest)}
  rescue
    ArgumentError -> {:badrpc, :invalid_response, rest}
  end

  def decode(<<0>> <> rest) do
    {:goodrpc, Plug.Crypto.non_executable_binary_to_term(rest)}
  rescue
    ArgumentError -> {:badrpc, :invalid_response, rest}
  end

  def decode(bin) do
    {:badrpc, :invalid_response, bin}
  end
end
