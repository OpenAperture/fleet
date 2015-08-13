defmodule OpenAperture.Fleet.Mixfile do
  use Mix.Project

  def project do
    [app: :openaperture_fleet,
     version: "0.0.1",
     elixir: "~> 1.0",
     deps: deps]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [applications: [:logger, :fleet_api],
     mod: {OpenAperture.Fleet, []}]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type `mix help deps` for more examples and options
  defp deps do
    [
      {:ex_doc, "0.7.3", only: :test},
      {:earmark, "0.1.17", only: :test}, 
            
      {:fleet_api, "~> 0.0.15", override: true},
      {:uuid, "~> 0.1.5" },
      {:meck, "0.8.2", only: :test},
    ]
  end
end
