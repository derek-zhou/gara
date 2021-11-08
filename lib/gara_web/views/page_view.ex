defmodule GaraWeb.PageView do
  use GaraWeb, :view
  import Surface

  alias GaraWeb.Welcome

  def render("index.html", assigns) do
    ~F'<Welcome rooms={@rooms} occupied={@occupied} />'
  end
  
end
