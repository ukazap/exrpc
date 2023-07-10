defmodule Exrpc.MFA do
  @moduledoc """
  This module provides functions validate and create `{module, function, arity}` tuple.
  """

  @doc """
  Checks if the given `{module, function, arity}` or `&module.function/arity` is valid.

  ## Examples

      iex> Exrpc.MFA.valid?({Enum, :into, 2})
      true
      iex> Exrpc.MFA.valid?(&Enum.into/2)
      true
      iex> Exrpc.MFA.valid?(&Enum.into/255)
      true
      iex> Exrpc.MFA.valid?(&Enum.get_rich_quick/1)
      true
      iex> Exrpc.MFA.valid?(Enum)
      false
  """
  @spec valid?(mfa() | fun()) :: boolean()
  def valid?({mod, fun, arity})
      when is_atom(mod) and is_atom(fun) and is_integer(arity) and arity >= 0 do
    true
  end

  def valid?(fun) when is_function(fun), do: true
  def valid?(_), do: false

  @doc """
  Checks if the given `{module, function, arity}` or `&module.function/arity` is callable.

  ## Examples

      iex> Exrpc.MFA.callable?({Enum, :into, 2})
      true
      iex> Exrpc.MFA.callable?(&Enum.into/2)
      true
      iex> Exrpc.MFA.callable?(&Enum.into/255)
      false
      iex> Exrpc.MFA.callable?(&Enum.get_rich_quick/1)
      false
  """
  @spec callable?(mfa() | fun()) :: boolean()
  def callable?({mod, fun, arity}) do
    function_exported?(mod, fun, arity)
  end

  def callable?(fun) when is_function(fun) do
    info = Function.info(fun)
    function_exported?(info[:module], info[:name], info[:arity])
  end

  def callable?(_), do: false

  @doc """
  Creates `{module, function, arity}` tuple from the given `&module.function/arity` or `{module, function, arity}`.

  ## Examples

      iex> Exrpc.MFA.tuple({Enum, :into, 2})
      {Enum, :into, 2}
      iex> Exrpc.MFA.tuple(&Enum.into/2)
      {Enum, :into, 2}
  """
  @spec tuple(mfa() | fun()) :: mfa()
  def tuple(function) when is_function(function) do
    info = Function.info(function)

    module = Keyword.get(info, :module)
    function = Keyword.get(info, :name)
    arity = Keyword.get(info, :arity)

    {module, function, arity}
  end

  def tuple({module, function, arity}), do: {module, function, arity}

  @doc """
  Returns list of mfa tuples from the given module.

  ## Examples

      iex> defmodule Foo do
      iex>   def bar(), do: :ok
      iex>   def baz(), do: qux()
      iex>   defp qux(), do: :ok
      iex> end
      iex> Exrpc.MFA.list(Foo)
      [{Foo, :bar, 0}, {Foo, :baz, 0}]
      iex> Exrpc.MFA.list(NotAModule)
      []
  """
  @spec list(module()) :: list(mfa())
  def list(module) when is_atom(module) do
    module.__info__(:functions)
    |> Enum.map(fn {function, arity} -> {module, function, arity} end)
  rescue
    UndefinedFunctionError -> []
  end
end
