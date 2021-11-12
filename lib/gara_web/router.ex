defmodule GaraWeb.Router do
  use GaraWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :put_root_layout, {GaraWeb.LayoutView, :root}
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", GaraWeb do
    pipe_through :browser

    get "/", PageController, :index
    post "/create", PageController, :create
    get "/room/:name", PageController, :room
  end

  # Other scopes may use custom stacks.
  # scope "/api", GaraWeb do
  #   pipe_through :api
  # end

  # Enables LiveDashboard only for development
  #
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).
  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: GaraWeb.Telemetry
    end
  end
end
