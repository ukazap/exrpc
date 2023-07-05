defmodule Exrpc.Server do
  @moduledoc false

  use Supervisor

  require Logger

  @spec start_link(keyword) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(opts) do
    mfa_list =
      opts
      |> Keyword.get(:mfa_list, [])
      |> Enum.uniq()
      |> Enum.filter(&Exrpc.MFA.valid?/1)
      |> case do
        [] -> raise ArgumentError, "invalid or empty mfa list"
        list -> list
      end

    init_arg = %{
      name: Keyword.fetch!(opts, :name),
      bandit_options: Keyword.get(opts, :bandit_options, []),
      mfa_list: mfa_list,
      port: Keyword.fetch!(opts, :port)
    }

    Supervisor.start_link(__MODULE__, init_arg, name: :"#{__MODULE__.Supervisor}_#{opts[:name]}")
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
  def init(%{name: name, bandit_options: bandit_options, mfa_list: mfa_list, port: port}) do
    {:ok, mfa_lookup} = Exrpc.MFA.Lookup.create(mfa_list)

    Logger.info("Exrpc: starting server #{name}")

    children = [
      {Bandit,
        Keyword.merge(bandit_options, [
          plug: {Exrpc.Server.Plug, mfa_lookup},
          port: port
        ])
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
