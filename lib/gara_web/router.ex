defmodule GaraWeb.Router do
  use GaraWeb, :router
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :put_root_layout, {GaraWeb.LayoutView, :root}
    plug :put_secure_browser_headers
  end

  scope "/", GaraWeb do
    pipe_through :browser

    get "/", PageController, :index
    post "/create", PageController, :create
    live "/room/:name", RoomLive, :chat
    live_dashboard "/dashboard", metrics: GaraWeb.Telemetry
  end
end
