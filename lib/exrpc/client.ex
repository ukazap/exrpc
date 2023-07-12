defmodule Exrpc.Client do
  use Supervisor
  use Memoize

  require Logger

  @type t :: pid() | atom()

  @doc false
  def via(client, key \\ make_ref()) do
    {:via, PartitionSupervisor, {client, key}}
  end

  @doc false
  def task_via(client, key \\ make_ref()) do
    {:via, PartitionSupervisor, {task_supervisor_name(client), key}}
  end

  @doc false
  defmemo task_supervisor_name(client) do
    :"#{client}.TaskSupervisor"
  end

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    init_arg = %{
      client: Keyword.fetch!(opts, :name),
      host: Keyword.fetch!(opts, :host),
      port: Keyword.fetch!(opts, :port)
    }

    Supervisor.start_link(__MODULE__, init_arg)
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, name: Keyword.fetch!(opts, :name)},
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @impl Supervisor
  def init(%{client: client, host: host, port: port}) do
    Logger.info("[#{__MODULE__}] #{client} connecting to #{host}:#{port}")

    children = [
      {PartitionSupervisor, child_spec: {Redix, host: host, port: port}, name: client},
      {PartitionSupervisor, child_spec: Task.Supervisor, name: task_supervisor_name(client)},
      {Exrpc.Client.Info, client}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
