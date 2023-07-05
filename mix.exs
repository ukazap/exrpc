defmodule Exrpc.MixProject do
  use Mix.Project

  def project do
    [
      app: :exrpc,
      description: "Elixir RPC over HTTP/2",
      package: package(),
      version: "0.1.2",
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

  @dev_deps [
    {:benchee, "~> 1.1", only: :test},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:sobelow, "~> 0.12", only: [:dev, :test], runtime: false}
  ]

  defp deps do
    [
      {:bandit, "~> 0.7.7"},
      {:finch, "~> 0.16.0"},
      {:plug_crypto, "~> 1.2"}
    ] ++ @dev_deps
  end

  defp aliases do
    [
      check: ["format --check-formatted", "credo --strict", "sobelow"]
    ]
  end
end
