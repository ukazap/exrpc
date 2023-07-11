defmodule Exrpc.MixProject do
  use Mix.Project

  @version "0.3.6"
  @url "https://github.com/ukazap/exrpc"

  def project do
    [
      app: :exrpc,
      description: "Simple Elixir RPC",
      package: package(),
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def package do
    [
      maintainers: ["Ukaza Perdana", "Wildan Fathan"],
      licenses: ["MIT"],
      links: %{GitHub: @url}
    ]
  end

  defp deps do
    [
      {:benchee, "~> 1.1", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.30.1", only: :dev, runtime: :false},
      {:sobelow, "~> 0.12", only: [:dev, :test], runtime: false},
      {:nimble_pool, "~> 1.0"},
      {:plug_crypto, "~> 1.2"},
      {:thousand_island, "~> 0.6.7"}
    ]
  end

  defp docs do
    [
      main: "Exrpc",
      source_ref: @version,
      source_url: @url
    ]
  end

  defp aliases do
    [
      check: ["format --check-formatted", "credo --strict", "sobelow"]
    ]
  end
end
