defmodule Exrpc.MFALookup do
  @moduledoc """
  Function allowlist and lookup table.

  Each functions exposed to clients is assigned a unique integer ID, This allows the server to enforce a function allowlist and the client can make RPC call by transmitting function ID instead of module and function atoms.

  **Internal details**: the lookup table is a tuple of two ETS tables, `{mfa2id, id2mfa}`, both of which are owned by the pid that created the table. The first table maps MFAs to IDs, the second table vice versa.

  ## Example

      iex> {:ok, lookup} = Exrpc.MFALookup.create([
      ...>   {Greeter, :hello, 1},
      ...>   {Greeter, :goodbye, 1}
      ...> ])
      iex> Exrpc.MFALookup.mfa_to_id(lookup, {Greeter, :hello, 1})
      0
      iex> Exrpc.MFALookup.id_to_mfa(lookup, 0)
      {Greeter, :hello, 1}
  """

  @type t :: {:ets.tid(), :ets.tid()}

  @doc """
  Create a lookup table from a list of MFAs.

  ## Examples

      iex> Exrpc.MFALookup.create([])
      {:error, :empty_list}
      iex> {:ok, {_mfa2id, _id2mfa}} = Exrpc.MFALookup.create([
      ...>   {Greeter, :hello, 1},
      ...>   {Greeter, :goodbye, 1}
      ...> ])
  """
  @spec create(list(mfa())) :: {:ok, t()} | {:error, atom()}
  def create([]), do: {:error, :empty_list}

  def create(mfa_list) when is_list(mfa_list) do
    mfa_list
    |> Enum.filter(&Exrpc.MFA.valid?/1)
    |> Enum.map(&Exrpc.MFA.tuple/1)
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

  @doc """
  Get a list of MFAs.

  ## Examples

      iex> {:ok, lookup} = Exrpc.MFALookup.create([
      ...>   {Greeter, :hello, 1},
      ...>   {Greeter, :goodbye, 1}
      ...> ])
      iex> Exrpc.MFALookup.to_list(lookup)
      [{Greeter, :hello, 1}, {Greeter, :goodbye, 1}]
  """
  @spec to_list(t()) :: [mfa()] | {:error, :invalid_mfa_lookup}
  def to_list({mfa2id, _} = _mfa_lookup) do
    mfa2id
    |> :ets.tab2list()
    |> Enum.sort_by(fn {_, id} -> id end)
    |> Enum.map(fn {fun, _} -> fun end)
  rescue
    ArgumentError -> {:error, :invalid_mfa_lookup}
  end

  @doc """
  Get the ID of an MFA.

  ## Examples

      iex> {:ok, lookup} = Exrpc.MFALookup.create([
      ...>   {Greeter, :hello, 1},
      ...>   {Greeter, :goodbye, 1}
      ...> ])
      iex> Exrpc.MFALookup.mfa_to_id(lookup, {Greeter, :hello, 1})
      0
      iex> Exrpc.MFALookup.mfa_to_id(lookup, {Greeter, :goodbye, 1})
      1
      iex> Exrpc.MFALookup.mfa_to_id(lookup, {Greeter, :heyyyy, 1})
      nil
  """
  @spec mfa_to_id(t(), mfa()) :: integer() | nil | {:error, :invalid_mfa_lookup}
  def mfa_to_id({mfa2id, _} = _mfa_lookup, {module_name, function_name, arity} = _mfa) do
    case :ets.lookup(mfa2id, {module_name, function_name, arity}) do
      [{_, id}] -> id
      [] -> nil
    end
  rescue
    ArgumentError -> {:error, :invalid_mfa_lookup}
  end

  def mfa_to_id(_, _), do: {:error, :invalid_mfa_lookup}

  @doc """
  Get MFA by ID.

  ## Examples

      iex> {:ok, lookup} = Exrpc.MFALookup.create([
      ...>   {Greeter, :hello, 1},
      ...>   {Greeter, :goodbye, 1}
      ...> ])
      iex> Exrpc.MFALookup.id_to_mfa(lookup, 0)
      {Greeter, :hello, 1}
      iex> Exrpc.MFALookup.id_to_mfa(lookup, 1)
      {Greeter, :goodbye, 1}
      iex> Exrpc.MFALookup.id_to_mfa(lookup, 2)
      nil
  """
  @spec id_to_mfa(t(), integer()) :: mfa() | nil | {:error, :invalid_mfa_lookup}
  def id_to_mfa({_, id2mfa} = _mfa_lookup, id) do
    case :ets.lookup(id2mfa, id) do
      [{_, {module_name, function_name, arity}}] -> {module_name, function_name, arity}
      [] -> nil
    end
  rescue
    ArgumentError -> {:error, :invalid_mfa_lookup}
  end

  def id_to_mfa(_, _), do: {:error, :invalid_mfa_lookup}
end
