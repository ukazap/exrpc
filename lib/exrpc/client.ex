defmodule Exrpc.Client do
  @moduledoc false

  use Supervisor

  require Logger

  @spec start_link(keyword) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    scheme = Keyword.get(opts, :scheme, :http)
    host = Keyword.fetch!(opts, :host)
    port = Keyword.fetch!(opts, :port)

    init_arg = [
      name: name,
      base_url: "#{scheme}://#{host}:#{port}"
    ]

    Supervisor.start_link(__MODULE__, init_arg, name: :"#{__MODULE__.Supervisor}_#{name}")
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
    Logger.info("Exrpc: starting client #{init_arg[:name]} for #{init_arg[:base_url]}")

    children = [
      {Finch,
        name: init_arg[:name],
        pools: %{
          default: [protocol: :http2]
      }},
      {Exrpc.Client.Endpoint, init_arg}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
