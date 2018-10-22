defmodule Aetestframework.MixProject do
  use Mix.Project

  def project do
    [
      app: :aetestframework,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:exconstructor, "~> 1.1"},
      {:aehttpclient, in_umbrella: true}
    ]
  end
end
