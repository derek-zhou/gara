defmodule GaraWeb.RoomLive do
  use Surface.LiveView
  import GaraWeb.Gettext
  require Logger

  use Phoenix.VerifiedRoutes,
    router: GaraWeb.Router,
    endpoint: GaraWeb.Endpoint,
    statics: ~w(css images js)

  alias Gara.{Room, Rooms, WaitingRooms, RoomsByPublicTopic}
  alias Phoenix.LiveView.Socket
  alias Surface.Components.Link
  alias GaraWeb.{Main, Header, Chat, History, Countdown}

  # client side state
  data tz_offset, :integer, default: 0
  data preferred_nick, :any, default: nil
  data client_id, :any, default: nil

  # states
  data room_name, :string, default: ""
  data room_pid, :pid, default: nil
  data room_ref, :any, default: nil
  data room_stat, :any, default: nil
  data room_locked?, :boolean, default: false
  data want_locked?, :boolean, default: false
  data participants, :list, default: []
  # :unkoown, :exist, :joined, :hangup or :waiting
  data room_status, :atom, default: :unknown
  data nick, :string, default: ""
  data uid, :any, default: nil
  data waiting_minutes, :integer, default: 0
  # :text, :image or :file
  data input_mode, :atom, default: :text
  # upload
  # {size, name, offset} if name is nil then it is an image
  data attachment, :tuple, default: nil
  data preview_url, :string, default: ""
  data uploading, :boolean, default: false
  data history, :list, default: []
  # temporary state
  data messages, :list, default: []

  # for GUI
  data show_info, :boolean, default: false
  data page_url, :string, default: ""

  def mount(_params, _session, socket) do
    if connected?(socket) do
      values = get_connect_params(socket)

      {
        :ok,
        socket
        |> fetch_tz_offset(values)
        |> fetch_preferred_nick(values)
        |> fetch_locale(values)
        |> fetch_token(values),
        temporary_assigns: [messages: []]
      }
    else
      {:ok, socket, temporary_assigns: [messages: []]}
    end
  end

  def handle_params(
        %{"name" => name},
        _url,
        %Socket{assigns: %{live_action: :chat}} = socket
      ) do
    socket = assign(socket, room_name: name)

    if connected?(socket) do
      case Registry.lookup(Rooms, name) do
        [] -> {:noreply, mount_waiting_room(socket)}
        [{pid, _}] -> {:noreply, mount_chat_room(socket, pid)}
      end
    else
      case Registry.lookup(Rooms, name) do
        [] -> {:noreply, socket}
        [{pid, _}] -> {:noreply, static_chat_room(socket, pid)}
      end
    end
  end

  defp mount_waiting_room(%Socket{assigns: %{room_name: name}} = socket) do
    case WaitingRooms.knock(name) do
      {:error, :no_entry} ->
        socket
        |> put_flash(:error, gettext("Room closed already"))
        |> assign(page_title: gettext("Room closed already"))
        |> push_event("set_token", %{token: ""})
        |> push_event("leave", %{})

      {:error, :capacity} ->
        socket
        |> put_flash(:error, gettext("All rooms are occupied, please come back later"))
        |> assign(page_title: gettext("All rooms are occupied, please come back later"))
        |> push_event("leave", %{})

      {:error, :expired} ->
        socket
        |> put_flash(:error, gettext("Room closed already"))
        |> assign(page_title: gettext("Room closed already"))
        |> push_event("set_token", %{token: ""})
        |> push_event("leave", %{})

      {:wait, minutes, topic} ->
        if connected?(socket), do: Process.send_after(self(), :count_down, 60_000)
        mtext = gettext("minutes")

        assign(socket,
          page_title: "(zzz #{minutes} #{mtext}) #{topic}",
          waiting_minutes: minutes,
          room_status: :waiting
        )

      {:ok, pid} ->
        mount_chat_room(socket, pid)
    end
  end

  defp static_chat_room(%Socket{assigns: %{room_name: name}} = socket, pid) do
    stat = Room.stat(pid)
    page_url = if stat.canonical?, do: stat.topic, else: url(~p"/room/#{name}")

    socket
    |> assign(
      room_stat: stat,
      page_title: "(#{stat.active}) #{stat.topic}",
      page_url: page_url,
      room_status: :exist,
      page_title: "#{stat.topic} -- GARA",
      history: Enum.reverse(stat.history)
    )
  end

  defp mount_chat_room(socket, pid) do
    socket
    |> static_chat_room(pid)
    |> join_chat_room(pid)
  end

  defp join_chat_room(
         %Socket{assigns: %{preferred_nick: preferred_nick, client_id: old_id}} = socket,
         pid
       ) do
    case Room.join(pid, old_id, preferred_nick) do
      {:error, _} ->
        socket
        |> put_flash(:error, gettext("No space in room"))
        |> push_event("leave", %{})

      {id, nick, participants, messages, locked?} ->
        socket =
          if nick == preferred_nick do
            put_flash(socket, :info, gettext("Welcome back, ") <> nick)
          else
            put_flash(
              socket,
              :info,
              gettext("Your temporary nickname is: ") <>
                nick <>
                ". " <>
                gettext("You should change it by clicking the top right corner")
            )
          end

        socket
        |> assign(
          room_pid: pid,
          room_ref: Process.monitor(pid),
          uid: id,
          nick: nick,
          room_status: :joined,
          participants: participants,
          history: [],
          messages: messages,
          want_locked?: locked?,
          room_locked?: locked?
        )
        |> push_event("set_token", %{token: IO.iodata_to_binary(:erlang.ref_to_list(id))})
    end
  end

  defp hop_room(%Socket{assigns: %{room_pid: room, room_ref: ref, uid: uid}} = socket, name) do
    case Registry.lookup(Rooms, name) do
      [{pid, _}] ->
        Room.advertize(room, uid, pid)
        Process.demonitor(ref)
        Room.break(room, uid)

        socket
        |> assign(room_name: name)
        |> push_event("set_url", %{url: ~p"/room/#{name}"})
        |> mount_chat_room(pid)

      _ ->
        put_flash(socket, :error, gettext("hopping failed"))
    end
  end

  def handle_info(:hangup, socket) do
    {
      :noreply,
      socket
      |> assign(room_status: :hangup)
      |> put_flash(:warning, gettext("Server hangup"))
      |> push_event("leave", %{})
    }
  end

  def handle_info(:count_down, socket) do
    {:noreply, mount_waiting_room(socket)}
  end

  def handle_info({:DOWN, _, _, _, _}, socket) do
    {
      :noreply,
      socket
      |> assign(room_status: :hangup)
      |> put_flash(:warning, gettext("Server crashed"))
      |> push_event("leave", %{})
    }
  end

  def handle_info({:user_message, _mid, _ts, _nick, _msg} = message, socket) do
    {:noreply, assign(socket, messages: [message])}
  end

  def handle_info({:private_message, _mid, _ts, _nick, _msg} = message, socket) do
    {:noreply, assign(socket, messages: [message])}
  end

  def handle_info(
        {:leave_message, _mid, _ts, nick} = message,
        %Socket{assigns: %{participants: participants, room_stat: stat}} = socket
      ) do
    participants = Enum.reject(participants, &(&1 == nick))

    {
      :noreply,
      assign(socket,
        page_title: "(#{length(participants)}) #{stat.topic}",
        messages: [message],
        participants: participants
      )
    }
  end

  def handle_info({:lock_message, _mid, _ts, v} = message, socket) do
    {:noreply, assign(socket, messages: [message], room_locked?: v)}
  end

  def handle_info(
        {:join_message, _mid, _ts, nick} = message,
        %Socket{assigns: %{participants: participants, room_stat: stat}} = socket
      ) do
    participants = Enum.reject(participants, &(&1 == nick))
    participants = [nick | participants]

    {
      :noreply,
      assign(socket,
        page_title: "(#{length(participants)}) #{stat.topic}",
        messages: [message],
        participants: participants
      )
    }
  end

  def handle_info(
        {:rename_message, _mid, _ts, old_nick, new_nick} = message,
        %Socket{assigns: %{participants: participants}} = socket
      ) do
    participants = Enum.reject(participants, &(&1 == old_nick))
    participants = [new_nick | participants]

    {:noreply, assign(socket, messages: [message], participants: participants)}
  end

  def handle_event("leave", _, %Socket{assigns: %{room_pid: room, uid: uid}} = socket) do
    Room.leave(room, uid)

    {
      :noreply,
      socket
      |> assign(room_status: :hangup, show_info: false)
      |> put_flash(:info, gettext("You left"))
      |> push_event("set_token", %{token: ""})
      |> push_event("leave", %{})
    }
  end

  def handle_event("lock", _, %Socket{assigns: %{room_pid: room, uid: uid}} = socket) do
    Room.try_lock(room, uid)
    {:noreply, assign(socket, want_locked?: true)}
  end

  def handle_event("unlock", _, %Socket{assigns: %{room_pid: room, uid: uid}} = socket) do
    Room.try_unlock(room, uid)
    {:noreply, assign(socket, want_locked?: false)}
  end

  def handle_event("fork", %{"topic" => new_topic}, socket) do
    case Room.new_room(new_topic) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("forking failed"))}

      :ignore ->
        case Registry.lookup(RoomsByPublicTopic, new_topic) do
          [] -> {:noreply, put_flash(socket, :error, gettext("forking failed"))}
          [{_pid, name}] -> {:noreply, hop_room(socket, name)}
        end

      name ->
        {:noreply, hop_room(socket, name)}
    end
  end

  def handle_event(
        "rename",
        %{"name" => new_nick},
        %Socket{assigns: %{room_pid: room, uid: uid}} = socket
      ) do
    case Room.rename(room, uid, new_nick) do
      :ok ->
        {
          :noreply,
          socket
          |> assign(nick: new_nick, show_info: false)
          |> push_event("set_preferred_nick", %{nick: new_nick})
          |> clear_flash()
        }

      {:error, :eexist} ->
        {:noreply, put_flash(socket, :error, gettext("The nickname is taken"))}

      {:error, :enodev} ->
        {:noreply, put_flash(socket, :error, gettext("Room closed already"))}

      {:error, :einval} ->
        {:noreply, put_flash(socket, :error, gettext("The nickname is invalid"))}
    end
  end

  def handle_event(
        "message",
        %{"text" => text},
        %Socket{assigns: %{room_pid: room, uid: uid}} = socket
      ) do
    %URI{scheme: s, port: p, host: h} = URI.parse(url(~p"/"))
    trimmed = String.trim(text)

    case URI.parse(trimmed) do
      %URI{scheme: ^s, port: ^p, host: ^h, path: "/room/" <> name} ->
        if Room.advertize(room, uid, name) do
          {:noreply, clear_flash(socket)}
        else
          {:noreply, put_flash(socket, :error, gettext("Room closed already"))}
        end

      %URI{scheme: "https"} ->
        Room.post(room, uid, trimmed)
        {:noreply, clear_flash(socket)}

      %URI{scheme: "http"} ->
        Room.post(room, uid, trimmed)
        {:noreply, clear_flash(socket)}

      _ ->
        Room.say(room, uid, text)
        {:noreply, clear_flash(socket)}
    end
  end

  def handle_event(
        "send_attachment",
        _params,
        %Socket{
          assigns: %{
            room_pid: room,
            uid: uid,
            uploading: false,
            attachment: {_, name, _}
          }
        } = socket
      ) do
    case name do
      nil -> Room.flaunt(room, uid)
      _ -> Room.attach(room, uid, name)
    end

    {
      :noreply,
      socket
      |> assign(input_mode: :text, attachment: nil)
      |> push_event("clear_attachment", %{})
      |> clear_flash()
    }
  end

  def handle_event("click_nick", _, %Socket{assigns: %{show_info: true}} = socket) do
    {
      :noreply,
      socket
      |> assign(show_info: false)
      |> clear_flash()
    }
  end

  def handle_event("click_nick", _, %Socket{assigns: %{show_info: false}} = socket) do
    {
      :noreply,
      socket
      |> assign(show_info: true)
      |> clear_flash()
    }
  end

  def handle_event("click_else", _, socket) do
    {
      :noreply,
      socket
      |> assign(show_info: false)
      |> clear_flash()
    }
  end

  def handle_event("click_image", _, %Socket{assigns: %{uploading: false}} = socket) do
    {
      :noreply,
      socket
      |> assign(input_mode: :image, attachment: nil)
      |> push_event("clear_attachment", %{})
    }
  end

  def handle_event("click_file", _, %Socket{assigns: %{uploading: false}} = socket) do
    {
      :noreply,
      socket
      |> assign(input_mode: :file, attachment: nil)
      |> push_event("clear_attachment", %{})
    }
  end

  def handle_event("click_text", _, %Socket{assigns: %{uploading: false}} = socket) do
    {
      :noreply,
      socket
      |> assign(input_mode: :text, attachment: nil)
      |> push_event("clear_attachment", %{})
    }
  end

  def handle_event("attach", %{"size" => size}, socket) when size > 100_000_000 do
    {
      :noreply,
      put_flash(socket, :error, gettext("File too big"))
    }
  end

  def handle_event(
        "attach",
        %{"size" => size, "name" => name, "url" => url},
        %Socket{assigns: %{uploading: false}} = socket
      ) do
    {
      :noreply,
      socket
      |> assign(attachment: {size, name, 0}, preview_url: url, uploading: true)
      |> clear_flash()
      |> push_event("read_attachment", %{offset: 0})
    }
  end

  def handle_event(
        "attach",
        %{"size" => size, "url" => url},
        %Socket{assigns: %{uploading: false}} = socket
      ) do
    {
      :noreply,
      socket
      |> assign(attachment: {size, nil, 0}, preview_url: url, uploading: true)
      |> clear_flash()
      |> push_event("read_attachment", %{offset: 0})
    }
  end

  def handle_event("attachment_chunk", %{"chunk" => chunk}, socket) do
    {:noreply, accept_chunk(socket, chunk)}
  end

  defp fetch_tz_offset(socket, %{"timezoneOffset" => offset}) do
    assign(socket, tz_offset: offset)
  end

  defp fetch_tz_offset(socket, _), do: socket

  defp fetch_locale(socket, %{"language" => language}) do
    case language |> language_to_locale() |> validate_locale() do
      nil -> :ok
      locale -> Gettext.put_locale(GaraWeb.Gettext, locale)
    end

    socket
  end

  defp fetch_locale(socket, _) do
    Gettext.put_locale(GaraWeb.Gettext, "en")
    socket
  end

  defp language_to_locale(language) do
    String.replace(language, "-", "_", global: false)
  end

  defp validate_locale(nil), do: nil

  defp validate_locale(locale) do
    supported_locales = Gettext.known_locales(GaraWeb.Gettext)

    case String.split(locale, "_") do
      [language, _] ->
        Enum.find([locale, language], fn locale ->
          locale in supported_locales
        end)

      [^locale] ->
        if locale in supported_locales do
          locale
        else
          nil
        end
    end
  end

  defp fetch_token(socket, %{"token" => token}) do
    try do
      id = token |> String.to_charlist() |> :erlang.list_to_ref()
      assign(socket, client_id: id)
    rescue
      _ ->
        socket
    end
  end

  defp fetch_token(socket, _), do: socket

  defp fetch_preferred_nick(socket, %{"preferred_nick" => nick}) do
    assign(socket, preferred_nick: nick)
  end

  defp fetch_preferred_nick(socket, _), do: socket

  defp accept_chunk(
         %Socket{
           assigns: %{
             room_pid: room,
             uid: uid,
             attachment: {size, name, offset}
           }
         } = socket,
         chunk
       ) do
    chunk = Base.decode64!(chunk)
    Room.stash(room, uid, chunk, offset)
    offset = offset + byte_size(chunk)

    cond do
      offset > size ->
        raise("Excessive data received in streaming")

      offset == size ->
        assign(socket,
          attachment: {size, name, offset},
          uploading: false
        )

      true ->
        socket
        |> assign(attachment: {size, name, offset})
        |> push_event("read_attachment", %{offset: offset})
    end
  end
end
