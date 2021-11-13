defmodule Gara.Room do
  @tick_interval 60 * 1000

  require Logger
  use GenServer, restart: :transient
  alias Gara.Roster
  alias Gara.RoomSupervisor
  alias Phoenix.PubSub

  defstruct [:name, :topic, :roster, :since, messages: []]

  @doc """
  create a new room for the given topic. return the room name if success or nil
  """
  def new_room(topic) do
    name = 6 |> :crypto.strong_rand_bytes() |> Base.url_encode64()

    case DynamicSupervisor.start_child(
           RoomSupervisor,
           {__MODULE__, %{name: name, topic: topic}}
         ) do
      {:error, _} -> nil
      {:ok, _} -> name
    end
  end

  def child_spec(args) do
    %{
      id: args[:name],
      start: {__MODULE__, :start_link, [args]},
      restart: :transient
    }
  end

  def start_link(%{name: name, topic: topic}) do
    GenServer.start_link(__MODULE__, {name, topic}, name: {:via, Registry, {Gara.Rooms, name}})
  end

  @doc """
  say something. Returns :ok
  """
  def say(room, id, msg), do: GenServer.cast(room, {:say, id, msg})

  @doc """
  leave the room. Returns :ok
  """
  def leave(room, id), do: GenServer.cast(room, {:leave, id})

  @doc """
  join the room with existing id. Returns {id, nick} if successful, :error if not
  """
  def join(room, id \\ nil), do: GenServer.call(room, {:join, self(), id})

  @doc """
  rename the user. Returns :ok if successful, :error if not
  """
  def rename(room, id, new_nick), do: GenServer.call(room, {:rename, id, new_nick})

  @doc """
  return a stat of the room in a map, or nil if room not found
  """
  def stat(room) do
    try do
      GenServer.call(room, :stat)
    catch
      :exit, _ -> nil
    end
  end

  @impl true
  def init({name, topic}) do
    Process.flag(:trap_exit, true)
    Process.flag(:max_heap_size, 1_000_000)
    Process.send_after(self(), :tick, @tick_interval)
    Logger.info("Room #{name}: room created with topic: #{topic}")
    {:ok, %__MODULE__{name: name, topic: topic, since: DateTime.utc_now(), roster: %Roster{}}}
  end

  @impl true
  def terminate(_reason, %__MODULE__{name: name, roster: roster}) do
    Logger.info("Room #{name}: closing")
    Roster.kill(roster)
  end

  @impl true
  def handle_info(:tick, %__MODULE__{name: name, roster: roster} = state) do
    roster = Roster.tick(roster)

    case Roster.size(roster) do
      0 ->
        Logger.info("Room #{name}: room is empty")
        {:stop, :normal, state}

      _ ->
        Process.send_after(self(), :tick, @tick_interval)
        {:noreply, %{state | roster: roster}}
    end
  end

  @impl true
  def handle_cast(
        {:say, id, msg},
        %__MODULE__{name: name, roster: roster, messages: messages} = state
      ) do
    case Roster.ping(roster, id) do
      :error ->
        Logger.warn("Room #{name}: Spurious user message received from #{id}")
        {:noreply, state}

      {:ok, roster} ->
        nick = Roster.get_name(roster, id)
        PubSub.local_broadcast(Gara.PubSub, "messages", {:user_message, nick, msg})
        messages = [{id, DateTime.utc_now(), msg} | messages]
        {:noreply, %{state | roster: roster, messages: messages}}
    end
  end

  @impl true
  def handle_cast(
        {:leave, id},
        %__MODULE__{name: name, roster: roster} = state
      ) do
    case Roster.get_name(roster, id) do
      nil ->
        Logger.warn("Room #{name}: Spurious leave message received from #{id}")
        {:noreply, state}

      nick ->
        roster = Roster.leave(roster, id)
        PubSub.local_broadcast(Gara.PubSub, "messages", {:leave_message, nick})
        {:noreply, %{state | roster: roster}}
    end
  end

  @impl true
  def handle_call({:join, pid, id}, _from, %__MODULE__{name: name, roster: roster} = state) do
    case Roster.join(roster, pid, id) do
      {:error, reason} ->
        Logger.warn("Room #{name}: room full")
        {:reply, {:error, reason}, state}

      {id, roster} ->
        nick = Roster.get_name(roster, id)
        Logger.info("Room #{name}: #{nick}(#{id}) joined")
        PubSub.local_broadcast(Gara.PubSub, "messages", {:join_message, nick})
        {:reply, {id, nick}, %{state | roster: roster}}
    end
  end

  @impl true
  def handle_call({:rename, id, new_nick}, _from, %__MODULE__{name: name, roster: roster} = state) do
    case Roster.rename(roster, id, new_nick) do
      :error ->
        Logger.warn("Room #{name}: #{id} rename failed")
        {:reply, :error, state}

      {:ok, roster, old_nick} ->
        Logger.info("Room #{name}: #{old_nick}(#{id}) renamed to #{new_nick}")
        PubSub.local_broadcast(Gara.PubSub, "messages", {:rename_message, old_nick, new_nick})
        {:reply, :ok, %{state | roster: roster}}
    end
  end

  @impl true
  def handle_call(:stat, _from, %__MODULE__{topic: topic, since: since, roster: roster} = state) do
    {:reply,
     %{topic: topic, since: since, people: Roster.fullsize(roster), active: Roster.size(roster)},
     state}
  end
end
