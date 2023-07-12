defmodule Exrpc.Client.Info do
  @moduledoc false

  use GenServer

  require Logger

  alias Exrpc.Client
  alias Exrpc.Client.InfoTable
  alias Exrpc.MFALookup
  alias Exrpc.Response

  @initial_backoff_ms 100
  @max_backoff_ms 2000
  @jitter_factor 0.2

  @spec start_link(Client.t()) :: Supervisor.on_start()
  def start_link(client) do
    GenServer.start_link(__MODULE__, client)
  end

  @impl GenServer
  def init(client) do
    InfoTable.create!(client)
    {:ok, client, {:continue, {:create_mfa_lookup, 0, nil}}}
  end

  @mfa_list_command Exrpc.Request.encode(:list)

  @impl GenServer
  def handle_continue({:create_mfa_lookup, retries, error}, client) do
    if retries > 0 do
      delay_ms = calculate_delay_ms(retries)

      Logger.error(
        "[#{__MODULE__}] failed to create MFA lookup for #{client}: #{inspect(error)}, retrying in #{delay_ms}ms"
      )

      :timer.sleep(delay_ms)
    end

    with {:ok, bin} <- Redix.command(Client.via(client), @mfa_list_command),
         {:goodrpc, mfa_list} when is_list(mfa_list) <- Response.decode(bin),
         {:ok, mfa_lookup} <- MFALookup.create(mfa_list),
         :ok <- InfoTable.put(client, mfa_lookup: mfa_lookup, mfa_list: mfa_list) do
      Logger.info("[#{__MODULE__}] created MFA lookup for #{client}")
      {:noreply, client}
    else
      error ->
        {:noreply, client, {:continue, {:create_mfa_lookup, retries + 1, error}}}
    end
  end

  defp calculate_delay_ms(retries) do
    backoff = :math.pow(2, retries) * @initial_backoff_ms
    capped_backoff = min(backoff, @max_backoff_ms)
    jitter = :rand.uniform() * (capped_backoff * @jitter_factor)
    trunc(capped_backoff + jitter)
  end
end
