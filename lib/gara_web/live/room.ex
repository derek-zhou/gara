defmodule GaraWeb.Room do
  use Surface.Component

  prop open, :boolean, default: false
  prop stat, :map, default: %{}
end
