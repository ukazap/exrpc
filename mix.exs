defmodule Exrpc.MixProject do
  use Mix.Project

  def project do
    [
      app: :exrpc,
      description: "Simple Elixir RPC",
      package: package(),
      version: "0.3.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
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
      links: %{GitHub: "https://github.com/ukazap/exrpc"}
    ]
  end

  defp deps do
    [
      {:benchee, "~> 1.1", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.12", only: [:dev, :test], runtime: false},
      {:nimble_pool, "~> 1.0"},
      {:plug_crypto, "~> 1.2"},
      {:thousand_island, "~> 0.6.7"}
    ]
  end

  defp aliases do
    [
      check: ["format --check-formatted", "credo --strict", "sobelow"]
    ]
  end
end
