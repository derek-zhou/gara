defmodule Gara.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias Gara.Defaults

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      GaraWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Gara.PubSub},
      # start the registry for chatrooms
      {Registry, keys: :unique, name: Gara.Rooms},
      # start the registry for chatrooms
      {Registry, keys: :unique, name: Gara.RoomsByPublicTopic},
      # start the supervisor for chatrooms
      {DynamicSupervisor,
       strategy: :one_for_one,
       name: Gara.RoomSupervisor,
       max_children: Defaults.default(:max_rooms)},
      # Start the CookieJar
      {CookieJar.Server, name: Gara.CookieJar},
      # Start the Endpoint (http/https)
      GaraWeb.Endpoint
      # Start a worker by calling: Gara.Worker.start_link(arg)
      # {Gara.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Gara.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GaraWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
