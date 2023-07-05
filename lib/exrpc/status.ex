defmodule Exrpc.Status do
  @type t :: 200 | 404 | 422 | :ok | :invalid_mfa | :error

  def status(200), do: :ok
  def status(400), do: :invalid_mfa
  def status(500), do: :error

  def code(:ok), do: 200
  def code(:invalid_mfa), do: 400
  def code(:error), do: 500
end
