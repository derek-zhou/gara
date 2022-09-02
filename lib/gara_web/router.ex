defmodule GaraWeb.Router do
  use GaraWeb, :router
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :put_root_layout, {GaraWeb.LayoutView, :root}
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", GaraWeb do
    pipe_through [:api]

    get "/stat", ApiController, :stat
    get "/stat/:name", ApiController, :stat
  end

  scope "/", GaraWeb do
    pipe_through :browser

    get "/", PageController, :index
    post "/create", PageController, :create
    live "/room/:name", RoomLive, :chat
    live_dashboard "/dashboard", metrics: GaraWeb.Telemetry

    # the catch all route has to be the last
    get "/*path", PageController, :catch_all
  end
end
