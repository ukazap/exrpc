defmodule Exrpc.MFA.Lookup do
  @moduledoc """
  Function allowlist and lookup table.

  Unlike `:rpc`, we don't transmit module and function names over the wire.
  Each function is assigned a unique integer ID, and the client sends the ID based on this lookup table.

    # Instantiate a new lookup table:
    iex> Exrpc.MFA.Lookup.create([])
    {:error, :empty_list}
    iex> {:ok, lookup} = Exrpc.MFA.Lookup.create([{Greeter, :hello, 1}, {Greeter, :goodbye, 1}, {Adder, :add, 2}])
    {:ok, lookup}
    # Route to ID and vice-versa:
    iex> Exrpc.MFA.Lookup.mfa_to_id(lookup, {Greeter, :hello, 1})
    0
    iex> Exrpc.MFA.Lookup.mfa_to_id(lookup, {Greeter, :goodbye, 1})
    1
    iex> Exrpc.MFA.Lookup.mfa_to_id(lookup, {Adder, :add, 2})
    2
    iex> Exrpc.MFA.Lookup.mfa_to_id(lookup, {Greeter, :howdy, 1})
    nil
    iex> Exrpc.MFA.Lookup.id_to_mfa(lookup, 0)
    {Greeter, :hello, 1}
    iex> Exrpc.MFA.Lookup.id_to_mfa(lookup, 1)
    {Greeter, :goodbye, 1}
    iex> Exrpc.MFA.Lookup.id_to_mfa(lookup, 2)
    {Adder, :add, 2}
    iex> Exrpc.MFA.Lookup.id_to_mfa(lookup, 3)
    nil
    # Convert lookup table to list (for transmitting to clients):
    iex> Exrpc.MFA.Lookup.to_list(lookup)
    [{Greeter, :hello, 1}, {Greeter, :goodbye, 1}, {Adder, :add, 2}]
  """

  @type t :: {atom | :ets.tid(), atom | :ets.tid()}
  @type function_name() :: atom()
  @type id() :: integer()

  @spec create(list(mfa())) :: {:ok, t()} | {:error, atom()}
  def create([]), do: {:error, :empty_list}

  def create(mfa_list) when is_list(mfa_list) do
    mfa_list
    |> Enum.filter(&Exrpc.MFA.valid?/1)
    |> Enum.map(&Exrpc.MFA.capture/1)
    |> case do
      [] ->
        {:error, :invalid_list}

      mfas ->
        mfa2id = :ets.new(:mfa2id, [:set, :public, {:read_concurrency, true}])
        mfa2id_list = Enum.with_index(mfas)
        true = :ets.insert(mfa2id, mfa2id_list)

        id2mfa = :ets.new(:id2mfa, [:set, :public, {:read_concurrency, true}])
        id2mfa_list = Enum.with_index(mfas, fn mfa, id -> {id, mfa} end)
        true = :ets.insert(id2mfa, id2mfa_list)

        {:ok, {mfa2id, id2mfa}}
    end
  end

  @spec to_list(t()) :: [mfa()]
  def to_list({mfa2id, _}) do
    mfa2id
    |> :ets.tab2list()
    |> Enum.sort_by(fn {_, id} -> id end)
    |> Enum.map(fn {fun, _} -> fun end)
  end

  @spec mfa_to_id(t(), mfa()) :: id() | nil
  def mfa_to_id({mfa2id, _}, {module_name, function_name, arity}) do
    case :ets.lookup(mfa2id, {module_name, function_name, arity}) do
      [{_, id}] -> id
      [] -> nil
    end
  end

  @spec id_to_mfa(t(), id()) :: {module(), function_name(), arity()} | nil
  def id_to_mfa({_, id2mfa}, id) do
    case :ets.lookup(id2mfa, id) do
      [{_, {module_name, function_name, arity}}] -> {module_name, function_name, arity}
      [] -> nil
    end
  end
end
