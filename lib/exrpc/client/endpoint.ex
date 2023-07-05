defmodule Exrpc.Client.Endpoint do
  @moduledoc false

  use GenServer

  require Logger

  alias Exrpc.Codec
  alias Exrpc.MFA

  @type t :: atom()

  @spec tab(t()) :: atom()
  def tab(endpoint), do: :"#{__MODULE__}_#{endpoint}"

  @spec info(t(), any(), any()) :: any()
  def info(endpoint, key, default \\ nil) do
    case :ets.lookup(tab(endpoint), key) do
      [{_, value}] -> value
      _ -> default
    end
  rescue
    ArgumentError -> nil
  end

  @spec start_link(keyword()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: :"#{__MODULE__}_#{opts[:name]}")
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, opts[:name]},
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @impl GenServer
  def init(init_arg) do
    name = Keyword.fetch!(init_arg, :name)

    tab =
      name
      |> tab()
      |> :ets.new([:set, :protected, :named_table, {:read_concurrency, true}])

    true = :ets.insert(tab, init_arg)

    state = %{
      name: name,
      base_url: Keyword.fetch!(init_arg, :base_url),
      tab: tab
    }

    {:ok, state, {:continue, :fetch_mfa_list}}
  end

  @impl GenServer
  def handle_continue(:fetch_mfa_list, state) do
    Logger.info("Exrpc: fetching MFA list for #{inspect(state.name)}")

    response =
      :get
      |> Finch.build(state.base_url)
      |> Finch.request(state.name)

    case response do
      {:ok, %{status: 200, body: bin}} ->
        {:ok, [_ | _] = mfa_list} = Codec.decode(bin)
        {:ok, mfa_lookup} = MFA.Lookup.create(mfa_list)
        true = :ets.insert(state.tab, {:mfa_lookup, mfa_lookup})
        {:noreply, state}
      {:error, %{reason: :econnrefused} = error} ->
        {:stop, error, state}
    end
  end
end
