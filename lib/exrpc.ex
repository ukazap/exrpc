defmodule Exrpc do
  @moduledoc false

  require Logger

  alias Exrpc.Client.Endpoint
  alias Exrpc.Codec
  alias Exrpc.MFA

  @receive_timeout 15_000

  @spec mfa_list(Endpoint.t()) :: list(mfa()) | nil
  def mfa_list(endpoint) do
    case Endpoint.info(endpoint, :mfa_lookup) do
      nil -> nil
      mfa_lookup -> MFA.Lookup.to_list(mfa_lookup)
    end
  end

  @spec call(Endpoint.t(), module(), atom(), list(), timeout()) :: {:badrpc, atom} | any()
  def call(endpoint, mod, fun, arg, timeout \\ @receive_timeout) when is_atom(mod) and is_atom(fun) and is_list(arg) do
    mfa = {mod, fun, length(arg)}

    with base_url <- Endpoint.info(endpoint, :base_url),
         {_, _} = mfa_lookup <- Endpoint.info(endpoint, :mfa_lookup, :empty_lookup),
         id when is_integer(id) <- MFA.Lookup.mfa_to_id(mfa_lookup, mfa),
         request <- build_request(base_url, id, arg),
         {:ok, %Finch.Response{status: 200, body: bin}} <- Finch.request(request, endpoint, receive_timeout: timeout),
         {:ok, result} <- Codec.decode(bin) do
      result
    else
      {:error, %Finch.Error{reason: :request_timeout}} -> {:badrpc, :timeout}
      :decode_error ->
        {:badrpc, :decode_error}
      :empty_lookup ->
        {:badrpc, :disconnected}
      error ->
        Logger.error("RPC call failed: #{inspect({mod, fun, arg})} (#{inspect(error)})")
        {:badrpc, :invalid_mfa}
    end
  end

  @spec call!(Endpoint.t(), module(), atom(), list(), timeout()) :: any()
  def call!(endpoint, mod, fun, arg, timeout \\ @receive_timeout) when is_atom(mod) and is_atom(fun) and is_list(arg) do
    case call(endpoint, mod, fun, arg, timeout) do
      {:badrpc, error} ->
        raise Exrpc.Error, "RPC call failed: #{inspect({mod, fun, arg})} (#{inspect(error)})"
      result ->
        result
    end
  end

  defp build_request(base_url, id, arg) do
    url = Path.join(base_url, Integer.to_string(id))
    body = Codec.encode(arg)
    Finch.build(:post, url, [], body)
  end
end
