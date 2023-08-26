defmodule Gara.Room do
  @tick_interval 60 * 1000

  require Logger
  use GenServer, restart: :transient
  alias Gara.{Roster, Message, Defaults, RoomSupervisor, Rooms, RoomsByPublicTopic}

  defstruct [
    :name,
    :topic,
    :roster,
    :since,
    messages: [],
    msg_id: 0,
    img_id: 0,
    canonical?: false,
    locked?: false
  ]

  @doc """
  create a new room name
  """
  def new_room_name(), do: 6 |> :crypto.strong_rand_bytes() |> Base.url_encode64()

  @doc """
  create a new room for the given topic. return the room name if success or nil
  """
  def new_room(topic, canonical? \\ false) do
    new_room(new_room_name(), topic, canonical?)
  end

  @doc """
  create a new room for the given topic and pre-allocated rom name.
  return the room name if success or nil
  """
  def new_room(name, topic, canonical?) do
    case DynamicSupervisor.start_child(
           RoomSupervisor,
           {__MODULE__, %{name: name, topic: topic, canonical?: canonical?}}
         ) do
      {:ok, _} -> name
      :ignore -> :ignore
      {:error, _} -> nil
    end
  end

  def child_spec(args) do
    %{
      id: args[:name],
      start: {__MODULE__, :start_link, [args]},
      restart: :transient
    }
  end

  def start_link(%{name: name, topic: topic, canonical?: canonical?}) do
    case GenServer.start_link(__MODULE__, {name, topic, canonical?},
           name: {:via, Registry, {Rooms, name}}
         ) do
      {:ok, pid} -> {:ok, pid}
      :ignore -> :ignore
      {:error, {:already_started, _pid}} -> :ignore
    end
  end

  @doc """
  say something. Returns :ok
  """
  def say(room, id, str) do
    trimmed = String.trim(str)

    case URI.parse(trimmed) do
      %URI{scheme: "https", port: 443, userinfo: nil} ->
        GenServer.cast(room, {:post, id, trimmed})

      %URI{scheme: "http", port: 80, userinfo: nil} ->
        GenServer.cast(room, {:post, id, trimmed})

      _ ->
        case Message.parse(str) do
          {msg, []} ->
            GenServer.cast(room, {:say, id, msg})

          {msg, recipients} ->
            GenServer.cast(room, {:whisper, id, msg, recipients})
        end
    end
  end

  @doc """
  stash data in a temp file, returns :ok
  """
  def stash(room, id, content, offset), do: GenServer.cast(room, {:stash, id, content, offset})

  @doc """
  flaunt an image from the temp file, returns :ok
  """
  def flaunt(room, id), do: GenServer.cast(room, {:flaunt, id})

  @doc """
  attach a file from the temp file, returns :ok
  """
  def attach(room, id, name), do: GenServer.cast(room, {:attach, id, name})

  @doc """
  leave the room. Returns :ok
  """
  def leave(room, id), do: GenServer.cast(room, {:leave, id})

  @doc """
  join the room with existing id.
  Returns {id, nick, participants, history, idle_percentage, want_locked?} if successful,
  {:error, reason} if not
  """
  def join(room, id \\ nil, preferred_nick \\ nil) do
    GenServer.call(room, {:join, self(), id, preferred_nick})
  end

  @doc """
  rename the user. Returns :ok if successful, {:error, reason} if not
  """
  def rename(room, id, new_nick), do: GenServer.call(room, {:rename, id, new_nick})

  @doc """
  try to lock the room. Return :ok
  """
  def try_lock(room, id), do: GenServer.cast(room, {:lock, id})

  @doc """
  try to unlock the room. Return :ok
  """
  def try_unlock(room, id), do: GenServer.cast(room, {:unlock, id})

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
  def init({name, topic, canonical?}) do
    case is_public_topic(topic) do
      true ->
        case Registry.register(RoomsByPublicTopic, topic, name) do
          {:ok, _} -> init_inner(name, topic, canonical?)
          {:error, {:already_registered, _pid}} -> :ignore
        end

      false ->
        init_inner(name, topic, false)
    end
  end

  defp init_inner(name, topic, canonical?) do
    Process.flag(:trap_exit, true)
    Process.flag(:max_heap_size, 100_000)
    Process.send_after(self(), :tick, @tick_interval)
    Logger.info("Room #{name}: room created with topic: #{topic}")
    upload_dir = Path.join([:code.priv_dir(:gara), "static", "uploads", name])
    File.rm_rf!(upload_dir)
    File.mkdir_p!(upload_dir)

    {
      :ok,
      %__MODULE__{
        name: name,
        topic: topic,
        since: NaiveDateTime.utc_now(),
        roster: %Roster{},
        canonical?: canonical?
      }
    }
  end

  defp is_public_topic(topic) do
    case URI.parse(topic) do
      %URI{scheme: "https"} -> true
      %URI{scheme: "http"} -> true
      _ -> false
    end
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
    new_roster = Roster.tick(roster)

    state =
      roster
      |> Roster.diff(new_roster)
      |> Enum.reduce(%{state | roster: new_roster}, &drop_one(&2, &1))
      |> repoll()

    case Roster.size(state.roster) do
      0 ->
        Logger.info("Room #{name}: room is empty")
        {:stop, :normal, state}

      _ ->
        Process.send_after(self(), :tick, @tick_interval)
        {:noreply, state}
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
        {:post, id, url},
        %__MODULE__{name: name, roster: roster, messages: messages, msg_id: msg_id} = state
      ) do
    case Roster.ping(roster, id) do
      :error ->
        Logger.warn("Room #{name}: Spurious user message received from #{id}")
        {:noreply, state}

      {:ok, roster} ->
        Message.fetch_preview(url, msg_id)
        nick = Roster.get_name(roster, id)
        now = NaiveDateTime.utc_now()
        msg = "<a href=\"#{url}\">#{url}</a>"
        Roster.broadcast(roster, {:user_message, msg_id, now, nick, msg})
        messages = [{msg_id, now, id, url} | messages]
        {:noreply, %{state | roster: roster, messages: messages, msg_id: msg_id + 1}}
    end
  end

  @impl true
  def handle_cast(
        {:say, id, msg},
        %__MODULE__{name: name, roster: roster, messages: messages, msg_id: msg_id} = state
      ) do
    case Roster.ping(roster, id) do
      :error ->
        Logger.warn("Room #{name}: Spurious user message received from #{id}")
        {:noreply, state}

      {:ok, roster} ->
        nick = Roster.get_name(roster, id)
        now = NaiveDateTime.utc_now()
        Roster.broadcast(roster, {:user_message, msg_id, now, nick, msg})
        messages = [{msg_id, now, id, msg} | messages]
        {:noreply, %{state | roster: roster, messages: messages, msg_id: msg_id + 1}}
    end
  end

  @impl true
  def handle_cast(
        {:whisper, id, msg, tos},
        %__MODULE__{name: name, roster: roster, msg_id: msg_id} = state
      ) do
    case Roster.ping(roster, id) do
      :error ->
        Logger.warn("Room #{name}: Spurious user message received from #{id}")
        {:noreply, state}

      {:ok, roster} ->
        nick = Roster.get_name(roster, id)
        now = NaiveDateTime.utc_now()

        tos
        |> MapSet.new()
        |> MapSet.put(nick)
        |> Enum.each(&Roster.unicast(roster, &1, {:private_message, msg_id, now, nick, msg}))

        {:noreply, %{state | roster: roster, msg_id: msg_id + 1}}
    end
  end

  @impl true
  def handle_cast({:stash, id, content, offset}, %__MODULE__{name: name} = state) do
    dest = Path.join([:code.priv_dir(:gara), "static", "uploads", name, "#{id}.tmp"])
    mode = if offset == 0, do: [:write, :raw], else: [:append, :raw]
    File.open(dest, mode, &IO.binwrite(&1, content))
    {:noreply, state}
  end

  @impl true
  def handle_cast(
        {:flaunt, id},
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
        src = Path.join([:code.priv_dir(:gara), "static", "uploads", name, "#{id}.tmp"])
        dest = Path.join([:code.priv_dir(:gara), "static", "uploads", name, "#{img_id}.jpg"])
        File.rename!(src, dest)
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
        {:attach, id, filename},
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
        src = Path.join([:code.priv_dir(:gara), "static", "uploads", name, "#{id}.tmp"])
        dest = Path.join([:code.priv_dir(:gara), "static", "uploads", name, "#{img_id}.bin"])
        File.rename!(src, dest)
        msg = Message.attach(filename, "/uploads/#{name}/#{img_id}.bin")
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
  def handle_cast({:leave, id}, state) do
    state = state |> drop_one(id) |> repoll()

    case Roster.size(state.roster) do
      0 -> {:stop, :normal, state}
      _ -> {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:lock, id}, state) do
    {:noreply, repoll(%{state | roster: Roster.lock(state.roster, id)})}
  end

  @impl true
  def handle_cast({:unlock, id}, state) do
    {:noreply, repoll(%{state | roster: Roster.unlock(state.roster, id)})}
  end

  @impl true
  def handle_call(
        {:join, pid, id, preferred_nick},
        _from,
        %__MODULE__{
          name: name,
          roster: roster,
          messages: messages,
          msg_id: msg_id,
          locked?: locked?
        } = state
      ) do
    case Roster.rejoin(roster, pid, id, preferred_nick, locked?) do
      {:error, reason} ->
        Logger.warn("Room #{name}: room full")
        {:reply, {:error, reason}, state}

      {id, roster} ->
        nick = Roster.get_name(roster, id)
        participants = Roster.participants(roster)
        {idle_percentage, want_locked?} = Roster.participant_info(roster, id)

        history =
          Enum.map(messages, fn {mid, time, id, msg} ->
            {:user_message, mid, time, Roster.get_name(roster, id), msg}
          end)

        Logger.info("Room #{name}: #{nick}(#{id}) joined")
        Roster.broadcast(roster, {:join_message, msg_id, NaiveDateTime.utc_now(), nick})

        {
          :reply,
          {id, nick, participants, history, idle_percentage, want_locked?},
          %{state | roster: roster, msg_id: msg_id + 1}
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
      {:error, reason} ->
        Logger.warn("Room #{name}: #{id} rename failed: #{reason}")
        {:reply, {:error, reason}, state}

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
  def handle_call(:stat, _from, state) do
    # to avoid unbounded messages
    messages = Enum.take(state.messages, Defaults.default(:max_history))

    history =
      Enum.map(messages, fn {mid, time, id, msg} ->
        {:user_message, mid, time, Roster.get_name(state.roster, id), msg}
      end)

    {:reply,
     %{
       name: state.name,
       topic: state.topic,
       since: state.since,
       people: Roster.fullsize(state.roster),
       active: Roster.size(state.roster),
       history: history,
       canonical?: state.canonical?
     }, state}
  end

  defp drop_one(%__MODULE__{name: name, roster: roster, msg_id: msg_id} = state, id) do
    case Roster.get_name(roster, id) do
      nil ->
        Logger.warn("Room #{name}: Spurious leave message received from #{id}")
        state

      nick ->
        roster = Roster.leave(roster, id)
        Roster.broadcast(roster, {:leave_message, msg_id, NaiveDateTime.utc_now(), nick})
        %{state | roster: roster, msg_id: msg_id + 1}
    end
  end

  defp repoll(%__MODULE__{roster: roster, msg_id: msg_id, locked?: locked?} = state) do
    if Roster.poll(roster, locked?) do
      Roster.broadcast(roster, {:lock_message, msg_id, NaiveDateTime.utc_now(), !locked?})
      %{state | msg_id: msg_id + 1, locked?: !locked?}
    else
      state
    end
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
