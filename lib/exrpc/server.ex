defmodule Exrpc.Server do
  use Supervisor

  require Logger

  alias Exrpc.MFA
  alias Exrpc.MFALookup
  alias Exrpc.Server.Handler
  alias ThousandIsland.Transports.TCP

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    port = Keyword.fetch!(opts, :port)
    shutdown_timeout = Keyword.get(opts, :shutdown_timeout, 15_000)
    if !is_integer(port), do: raise(ArgumentError, "invalid port #{inspect(port)}")

    mfa_list =
      opts
      |> Keyword.fetch!(:mfa_list)
      |> Enum.filter(&(MFA.valid?(&1) and MFA.callable?(&1)))
      |> Enum.uniq()
      |> case do
        [] -> raise ArgumentError, "invalid mfa_list"
        list -> list
      end

    init_arg = %{
      name: name,
      port: port,
      mfa_list: mfa_list,
      shutdown_timeout: shutdown_timeout
    }

    Supervisor.start_link(__MODULE__, init_arg, name: name)
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
    Logger.info("[#{__MODULE__}] #{init_arg.name} listening on port #{init_arg.port}")
    {:ok, mfa_lookup} = MFALookup.create(init_arg.mfa_list)

    {ThousandIsland,
     port: init_arg.port,
     handler_module: Handler,
     handler_options: %Handler.State{mfa_lookup: mfa_lookup},
     transport_module: TCP,
     transport_options: [keepalive: true],
     shutdown_timeout: init_arg.shutdown_timeout}
    |> Supervisor.child_spec(shutdown: init_arg.shutdown_timeout)
    |> List.wrap()
    |> Supervisor.init(strategy: :one_for_one)
  end
end
