defmodule Exrpc.Server.Router do
  use Plug.Router

  alias __MODULE__
  alias Exrpc.Codec
  alias Exrpc.MFA
  alias Exrpc.Status

  @spec route(Plug.Conn.t()) :: Plug.Conn.t()
  def route(conn), do: Router.call(conn, Router.init([]))

  plug :match
  plug :dispatch

  get "/" do
    body =
      conn.assigns.mfa_lookup
      |> MFA.Lookup.to_list()
      |> Codec.encode()

    conn
    |> send_resp(Status.code(:ok), body)
  end

  post "/:id" do
    with {mod, fun, arity} <- take_mfa(conn.assigns.mfa_lookup, id),
         {:arg, ^arity, arg} <- parse_body(conn),
         {:result, result} <- apply_mfa(mod, fun, arg) do
      {:ok, result}
    else
      :mfa_not_found -> :invalid_mfa
      :invalid_arg -> :invalid_mfa
      {:arg, _arity, _arg} -> :invalid_mfa
      {:error, error} -> {:error, error}
    end
    |> case do
      {status, data} ->
        send_resp(conn, Status.code(status), Codec.encode(data))
      status ->
        send_resp(conn, Status.code(status), "")
    end
  end

  match _ do
    send_resp(conn, Status.code(:invalid_mfa), "")
  end

  defp take_mfa(mfa_lookup, id) do
    case MFA.Lookup.id_to_mfa(mfa_lookup, String.to_integer(id)) do
      nil -> :mfa_not_found
      mfa -> mfa
    end
  rescue
    ArgumentError -> :mfa_not_found
  end

  defp parse_body(conn) do
    with {:ok, body, _} <- read_body(conn),
         {:ok, [_ | _] = arg} <- Codec.decode(body) do
      {:arg, length(arg), arg}
    else
      _ -> :invalid_arg
    end
  end

  defp apply_mfa(mod, fun, arg) do
    try do
      result = apply(mod, fun, arg)
      {:result, result}
    rescue
      error -> {:error, error}
    catch
      error -> {:error, error}
    end
  end
end
