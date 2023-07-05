defmodule Exrpc.Server.Plug do
  @behaviour Plug
  import Plug.Conn

  @impl Plug
  def init(mfa_lookup), do: mfa_lookup

  @impl Plug
  def call(conn, mfa_lookup) do
    conn
    |> assign(:mfa_lookup, mfa_lookup)
    |> Exrpc.Server.Router.route()
  end
end
