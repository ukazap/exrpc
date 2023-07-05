defmodule Exrpc.MFA do
  def valid?(fun) when is_function(fun) do
    case Function.info(fun, :type) do
      {:type, :external} -> true
      _ -> false
    end
  end

  def valid?({mod, fun, arity}) when is_atom(mod) and is_atom(fun) and is_integer(arity) and arity >= 0, do: true

  def valid?(_), do: false

  def capture(fun) when is_function(fun) do
    {:module, mod} = Function.info(fun, :module)
    {:name, name} = Function.info(fun, :name)
    {:arity, arity} = Function.info(fun, :arity)
    {mod, name, arity}
  end

  def capture({mod, fun, arity}), do: {mod, fun, arity}
end
