defmodule Gara.Room do
  @tick_interval 60 * 1000

  require Logger
  use GenServer, restart: :transient
  alias Gara.Roster
  alias Phoenix.PubSub

  defstruct [:name, :roster, messages: []]

  def child_spec(name: name) do
    %{
      id: name,
      start: {__MODULE__, :start_link, [[name: name]]},
      restart: :transient
    }
  end

  def start_link(name: name) do
    GenServer.start_link(__MODULE__, name, name: {:via, Registry, {Gara.Rooms, name}})
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

  @impl true
  def init(name) do
    Process.flag(:trap_exit, true)
    Process.send_after(self(), :tick, @tick_interval)
    {:ok, %__MODULE__{name: name, roster: %Roster{}}}
  end

  @impl true
  def terminate(_reason, %__MODULE__{name: name, roster: roster}) do
    Logger.info("Room #{name}: closing")
    Roster.kill(roster)
  end

  @impl true
  def handle_info(:tick, %__MODULE__{name: name, roster: roster} = state) do
    roster = Roster.tick(roster)

    if Roster.size(roster) == 0 do
      Logger.info("Room #{name}: room is empty")
      GenServer.stop(self())
    else
      Process.send_after(self(), :tick, @tick_interval)
    end

    {:noreply, %{state | roster: roster}}
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
end
