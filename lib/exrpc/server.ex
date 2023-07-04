defmodule Exrpc.Server do
  @moduledoc false

  use Supervisor

  alias Exrpc.MFA
  alias Exrpc.MFALookup
  alias Exrpc.Server.Handler

  def start_link(opts) do
    port = Keyword.fetch!(opts, :port)
    if !is_integer(port), do: raise(ArgumentError, "invalid port #{inspect(port)}")

    mfa_list =
      opts
      |> Keyword.fetch!(:mfa_list)
      |> Enum.filter(&MFA.valid?/1)
      |> Enum.uniq()
      |> case do
        [] -> raise ArgumentError, "invalid mfa_list"
        list -> list
      end

    # see https://hexdocs.pm/thousand_island/ThousandIsland.Transports.TCP.html
    transport_options = Keyword.get(opts, :transport_options, [])

    init_arg = %{
      port: port,
      mfa_list: mfa_list,
      transport_options: transport_options
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
    {:ok, mfa_lookup} = MFALookup.create(init_arg.mfa_list)

    children = [
      {ThousandIsland,
       port: init_arg.port,
       handler_module: Handler,
       handler_options: mfa_lookup,
       transport_module: ThousandIsland.Transports.TCP,
       transport_options: init_arg.transport_options}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
