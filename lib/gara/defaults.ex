defmodule Gara.Defaults do
  @app :gara

  def default(:room_capacity), do: default_value(:room_capacity, 16)
  def default(:idle_limit), do: default_value(:idle_limit, 60)
  def default(:init_idle), do: default_value(:init_idle, 55)
  def default(:max_rooms), do: default_value(:max_rooms, 16)
  def default(:max_history), do: default_value(:max_history, 100)

  defp default_value(key, default), do: Application.get_env(@app, key, default)
end
