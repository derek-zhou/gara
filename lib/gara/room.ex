defmodule Gara.Room do
  @tick_interval 60 * 1000

  require Logger
  use GenServer, restart: :transient
  alias Gara.{Roster, Message, Defaults, RoomSupervisor, Rooms}

  defstruct [:name, :topic, :roster, :since, messages: [], msg_id: 0, img_id: 0]

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
    GenServer.start_link(__MODULE__, {name, topic}, name: {:via, Registry, {Rooms, name}})
  end

  @doc """
  say something. Returns :ok
  """
  def say(room, id, str) do
    trimmed = String.trim(str)

    is_url =
      case URI.parse(trimmed) do
        %URI{scheme: "https", port: 443, userinfo: nil} -> true
        _ -> false
      end

    GenServer.cast(room, {:say, id, Message.parse(str), is_url, trimmed})
  end

  @doc """
  flaunt an image, Returns :ok
  """
  def flaunt(room, id, path), do: GenServer.cast(room, {:flaunt, id, File.read!(path)})

  @doc """
  leave the room. Returns :ok
  """
  def leave(room, id), do: GenServer.cast(room, {:leave, id})

  @doc """
  join the room with existing id. Returns {id, nick, participants, history} if successful,
  {:error, reason} if not
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
    Process.flag(:max_heap_size, 100_000)
    Process.send_after(self(), :tick, @tick_interval)
    Logger.info("Room #{name}: room created with topic: #{topic}")
    upload_dir = Path.join([:code.priv_dir(:gara), "static", "uploads", name])
    File.rm_rf!(upload_dir)
    File.mkdir_p!(upload_dir)

    {
      :ok,
      %__MODULE__{name: name, topic: topic, since: NaiveDateTime.utc_now(), roster: %Roster{}}
    }
  end

  @impl true
  def terminate(_reason, %__MODULE__{name: name, roster: roster}) do
    Logger.info("Room #{name}: closing")
    upload_dir = Path.join([:code.priv_dir(:gara), "static", "uploads", name])
    File.rm_rf!(upload_dir)
    Roster.broadcast(roster, :hangup)
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
  def handle_info(
        {:update, mid, msg},
        %__MODULE__{roster: roster, messages: messages} = state
      ) do
    {:noreply, %{state | messages: update_messages(messages, mid, msg, roster)}}
  end

  @impl true
  def handle_cast(
        {:say, id, msg, is_url, text},
        %__MODULE__{name: name, roster: roster, messages: messages, msg_id: msg_id} = state
      ) do
    case Roster.ping(roster, id) do
      :error ->
        Logger.warn("Room #{name}: Spurious user message received from #{id}")
        {:noreply, state}

      {:ok, roster} ->
        if is_url, do: Message.fetch_preview(text, msg_id)
        nick = Roster.get_name(roster, id)
        now = NaiveDateTime.utc_now()
        Roster.broadcast(roster, {:user_message, msg_id, now, nick, msg})
        messages = [{msg_id, now, id, msg} | messages]
        {:noreply, %{state | roster: roster, messages: messages, msg_id: msg_id + 1}}
    end
  end

  @impl true
  def handle_cast(
        {:flaunt, id, content},
        %__MODULE__{
          name: name,
          roster: roster,
          messages: messages,
          img_id: img_id,
          msg_id: msg_id
        } = state
      ) do
    case Roster.ping(roster, id) do
      :error ->
        Logger.warn("Room #{name}: Spurious user message received from #{id}")
        {:noreply, state}

      {:ok, roster} ->
        dest = Path.join([:code.priv_dir(:gara), "static", "uploads", name, "#{img_id}.jpg"])
        File.write!(dest, content)
        msg = Message.flaunt("/uploads/#{name}/#{img_id}.jpg")
        nick = Roster.get_name(roster, id)
        now = NaiveDateTime.utc_now()
        Roster.broadcast(roster, {:user_message, msg_id, now, nick, msg})
        messages = [{msg_id, now, id, msg} | messages]

        {
          :noreply,
          %{state | roster: roster, messages: messages, img_id: img_id + 1, msg_id: msg_id + 1}
        }
    end
  end

  @impl true
  def handle_cast(
        {:leave, id},
        %__MODULE__{name: name, roster: roster, msg_id: msg_id} = state
      ) do
    case Roster.get_name(roster, id) do
      nil ->
        Logger.warn("Room #{name}: Spurious leave message received from #{id}")
        {:noreply, state}

      nick ->
        roster = Roster.leave(roster, id)
        Roster.broadcast(roster, {:leave_message, msg_id, NaiveDateTime.utc_now(), nick})
        {:noreply, %{state | roster: roster, msg_id: msg_id + 1}}
    end
  end

  @impl true
  def handle_call(
        {:join, pid, id},
        _from,
        %__MODULE__{name: name, roster: roster, messages: messages, msg_id: msg_id} = state
      ) do
    case Roster.join(roster, pid, id) do
      {:error, reason} ->
        Logger.warn("Room #{name}: room full")
        {:reply, {:error, reason}, state}

      {id, roster} ->
        nick = Roster.get_name(roster, id)
        participants = Roster.participants(roster)
        # to avoid unbounded messages
        messages = Enum.take(messages, Defaults.default(:max_history))

        history =
          Enum.map(messages, fn {mid, time, id, msg} ->
            {:user_message, mid, time, Roster.get_name(roster, id), msg}
          end)

        Logger.info("Room #{name}: #{nick}(#{id}) joined")
        Roster.broadcast(roster, {:join_message, msg_id, NaiveDateTime.utc_now(), nick})

        {
          :reply,
          {id, nick, participants, history},
          %{state | roster: roster, messages: messages, msg_id: msg_id + 1}
        }
    end
  end

  @impl true
  def handle_call(
        {:rename, id, new_nick},
        _from,
        %__MODULE__{name: name, roster: roster, msg_id: msg_id} = state
      ) do
    case Roster.rename(roster, id, new_nick) do
      :error ->
        Logger.warn("Room #{name}: #{id} rename failed")
        {:reply, :error, state}

      {:ok, roster, old_nick} ->
        Logger.info("Room #{name}: #{old_nick}(#{id}) renamed to #{new_nick}")

        Roster.broadcast(
          roster,
          {:rename_message, msg_id, NaiveDateTime.utc_now(), old_nick, new_nick}
        )

        {:reply, :ok, %{state | roster: roster, msg_id: msg_id + 1}}
    end
  end

  @impl true
  def handle_call(:stat, _from, %__MODULE__{topic: topic, since: since, roster: roster} = state) do
    {:reply,
     %{topic: topic, since: since, people: Roster.fullsize(roster), active: Roster.size(roster)},
     state}
  end

  defp update_messages([], _mid, _msg, _roster), do: []

  defp update_messages([{mid, ts, id, _old} | tail], mid, msg, roster) do
    nick = Roster.get_name(roster, id)
    Roster.broadcast(roster, {:user_message, mid, ts, nick, msg})
    [{mid, ts, id, msg} | tail]
  end

  defp update_messages([head | tail], mid, msg, roster) do
    [head | update_messages(tail, mid, msg, roster)]
  end
end
