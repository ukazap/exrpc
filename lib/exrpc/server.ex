defmodule ExRPC.Server do
  @moduledoc false

  use Supervisor

  alias ExRPC.FunctionRoutes
  alias ExRPC.Server.Handler

  def start_link(opts) do
    mfa_list = Keyword.get(opts, :routes, [])
    routes =
      case FunctionRoutes.create(mfa_list) do
        {:ok, routes} -> routes
        {:error, _} -> raise ArgumentError, "invalid or empty list of routes"
      end

    init_arg = %{
      port: Keyword.fetch!(opts, :port),
      routes: routes
    }

    Supervisor.start_link(__MODULE__, init_arg, name: opts[:name])
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, opts[:name]},
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @impl Supervisor
  def init(init_arg) do
    children = [
      {ThousandIsland,
       port: init_arg.port, handler_module: Handler, handler_options: %{routes: init_arg.routes}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
