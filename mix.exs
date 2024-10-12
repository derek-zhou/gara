defmodule Gara.MixProject do
  use Mix.Project

  def project do
    [
      app: :gara,
      version: version(),
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers() ++ [:surface],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Gara.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:bandit, "~> 1.0"},
      {:surface, "~> 0.12.0"},
      {:md, "~> 0.9.1"},
      {:cookie_jar, "~> 1.1"},
      {:httpoison, "~> 1.8"},
      {:phoenix, "~> 1.7.2"},
      {:phoenix_html, "~> 3.2"},
      {:phoenix_live_reload, "~> 1.4.1", only: :dev},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:phoenix_live_view, "~> 0.20"},
      {:phoenix_view, "~> 2.0"},
      {:floki, ">= 0.33.0"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:gettext, "~> 0.18"},
      {:jason, "~> 1.2"}
    ]
  end

  defp version do
    case System.shell("git tag | tail -n1") do
      {tag, 0} ->
        case String.trim(tag) do
          "" -> "0.0.0"
          trimmed -> trimmed
        end

      _ ->
        "0.0.0"
    end
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      start: ["compile", "phx.server"],
      deploy: [
        "compile",
        "release --overwrite"
      ]
    ]
  end
end
