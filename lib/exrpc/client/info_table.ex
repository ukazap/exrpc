defmodule Exrpc.Client.InfoTable do
  @moduledoc false

  use Memoize

  alias Exrpc.Client

  @spec name(Client.t()) :: atom()
  defmemo name(client) do
    :"#{__MODULE__}_#{client}"
  end

  @spec create!(Client.t()) :: :ok | no_return()
  def create!(client) do
    table_name = name(client)
    :ets.new(table_name, [:set, :protected, :named_table, {:read_concurrency, true}])
  end

  @spec put(Client.t(), tuple() | list(tuple())) :: :ok | any()
  def put(client, tuple_or_list_of_tuples) do
    true = :ets.insert(name(client), tuple_or_list_of_tuples)
    :ok
  end

  @spec get(Client.t(), term()) :: term()
  @spec get(Client.t(), term(), term()) :: term()
  def get(client, key, default \\ nil) do
    case :ets.lookup(name(client), key) do
      [{_, value}] -> value
      _ -> default
    end
  rescue
    ArgumentError -> default
  end
end
