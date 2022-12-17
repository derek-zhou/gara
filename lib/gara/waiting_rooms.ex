defmodule Gara.WaitingRooms do
  # name of the ETS table
  @ets_waiting_rooms :roastidious_waiting_rooms

  alias :ets, as: ETS
  alias Gara.{Defaults, Room}

  @doc """
  init the data structures
  """
  def init() do
    ETS.new(@ets_waiting_rooms, [:named_table, :public])
  end

  @doc """
  open one wating room
  """
  def open(topic, minutes) do
    name = Room.new_room_name()
    timeout = System.monotonic_time(:second) + minutes * 60 + 59
    ETS.insert(@ets_waiting_rooms, {name, topic, timeout})
    name
  end

  @doc """
  knock on one waiting room
  """
  def knock(name) do
    now = System.monotonic_time(:second)
    limit = Defaults.default(:idle_limit) * 60

    case ETS.lookup(@ets_waiting_rooms, name) do
      [{^name, topic, timeout}] when timeout > now + 59 ->
        {:wait, div(timeout - now, 60), topic}

      [{^name, _topic, timeout}] when timeout <= now - limit ->
        ETS.delete(@ets_waiting_rooms, name)
        {:error, :expired}

      [{^name, topic, _timeout}] ->
        case Room.new_room(name, topic, false) do
          :ignore ->
            {:ok, name}

          ^name ->
            ETS.delete(@ets_waiting_rooms, name)
            {:ok, name}

          nil ->
            {:error, :capacity}
        end

      [] ->
        {:error, :no_entry}
    end
  end
end
