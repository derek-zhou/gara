defmodule Gara.WaitingRooms do
  alias :ets, as: ETS
  alias Gara.{Defaults, Room, Rooms}

  @doc """
  init the data structures
  """
  def init() do
    ETS.new(__MODULE__, [:named_table, :public])
  end

  @doc """
  open one wating room
  """
  def open(topic, minutes) do
    name = Room.new_room_name()
    timeout = System.monotonic_time(:second) + minutes * 60 + 59
    ETS.insert(__MODULE__, {name, topic, timeout})
    name
  end

  @doc """
  knock on one waiting room
  """
  def knock(name) do
    now = System.monotonic_time(:second)
    limit = Defaults.default(:idle_limit) * 60

    case ETS.lookup(__MODULE__, name) do
      [{^name, topic, timeout}] when timeout > now + 59 ->
        {:wait, div(timeout - now, 60), topic}

      [{^name, _topic, timeout}] when timeout <= now - limit ->
        ETS.delete(__MODULE__, name)
        {:error, :expired}

      [{^name, topic, _timeout}] ->
        case Room.new_room(name, topic, false) do
          :ignore ->
            case Registry.lookup(Rooms, name) do
              [] -> {:error, :expired}
              [{pid, _}] -> {:ok, pid}
            end

          ^name ->
            ETS.delete(__MODULE__, name)

            case Registry.lookup(Rooms, name) do
              [] -> {:error, :expired}
              [{pid, _}] -> {:ok, pid}
            end

          nil ->
            {:error, :capacity}
        end

      [] ->
        {:error, :no_entry}
    end
  end
end
