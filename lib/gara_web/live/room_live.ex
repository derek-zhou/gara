defmodule GaraWeb.RoomLive do
  use Surface.LiveView
  import GaraWeb.Gettext
  require Logger

  alias Gara.{Room, Rooms}
  alias Phoenix.LiveView.Socket
  alias GaraWeb.{Endpoint, Main, Header, Chat, Guardian}
  alias GaraWeb.Router.Helpers, as: Routes

  # client side state
  data tz_offset, :integer, default: 0

  # states
  data room_name, :string, default: ""
  data room_pid, :pid, default: nil
  data room_stat, :any, default: nil
  data participants, :list, default: []
  # :unkoown, :existed, :joined or :hangup
  data room_status, :atom, default: :unknown
  data nick, :string, default: ""
  data uid, :integer, default: 0
  data idle_percentage, :integer, default: 0
  # :text, :image or :file
  data input_mode, :atom, default: :text
  # upload
  # {size, name, offset, chunks} if name is nil then it is an image
  data attachment, :tuple, default: nil
  data preview_url, :string, default: ""
  data uploading, :boolean, default: false
  # temporary state
  data messages, :list, default: []

  # for GUI
  data show_info, :boolean, default: false
  data page_url, :string, default: ""

  def mount(%{"name" => room_name}, _session, %Socket{assigns: %{live_action: :chat}} = socket) do
    socket = assign(socket, room_name: room_name)

    socket =
      case Registry.lookup(Rooms, room_name) do
        [] ->
          socket
          |> put_flash(:error, gettext("Room closed already"))
          |> assign(page_title: gettext("Room closed already"))
          |> push_event("set_token", %{token: ""})
          |> push_event("leave", %{})

        [{pid, _}] ->
          stat = Room.stat(pid)

          socket =
            socket
            |> assign(
              room_pid: pid,
              room_stat: stat,
              page_title: "(#{stat.active}) #{stat.topic}",
              page_url:
                if(stat.canonical?,
                  do: stat.topic,
                  else: Routes.room_url(Endpoint, :chat, room_name)
                ),
              room_status: :existed
            )

          cond do
            connected?(socket) ->
              values = get_connect_params(socket)
              socket = fetch_tz_offset(socket, values)
              old_id = fetch_token(values, room_name)
              preferred_nick = fetch_preferred_nick(values)
              fetch_locale(values)
              Process.monitor(pid)

              case Room.join(pid, old_id, preferred_nick) do
                {:error, _} ->
                  socket
                  |> put_flash(:error, gettext("No space in room"))
                  |> push_event("leave", %{})

                {^old_id, nick, participants, messages, idle_percentage} ->
                  socket
                  |> assign(
                    uid: old_id,
                    nick: nick,
                    room_status: :joined,
                    participants: participants,
                    messages: messages,
                    idle_percentage: idle_percentage
                  )
                  |> put_flash(:info, gettext("Welcome back, ") <> nick)

                {id, ^preferred_nick, participants, messages, idle_percentage} ->
                  {:ok, token} = Guardian.build_token(id, room_name)

                  socket
                  |> assign(
                    uid: id,
                    nick: preferred_nick,
                    room_status: :joined,
                    participants: participants,
                    messages: messages,
                    idle_percentage: idle_percentage
                  )
                  |> push_event("set_token", %{token: token})

                {id, nick, participants, messages, idle_percentage} ->
                  {:ok, token} = Guardian.build_token(id, room_name)

                  socket
                  |> assign(
                    uid: id,
                    nick: nick,
                    room_status: :joined,
                    participants: participants,
                    messages: messages,
                    idle_percentage: idle_percentage
                  )
                  |> push_event("set_token", %{token: token})
                  |> put_flash(
                    :info,
                    gettext("Your temporary nickname is: ") <>
                      nick <>
                      ". " <>
                      gettext("You should change it by clicking the top right corner")
                  )
              end

            true ->
              assign(socket, messages: stat.history)
          end
      end

    {:ok, socket, temporary_assigns: [messages: []]}
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

  def handle_info({:tick, idle_percentage}, socket) do
    {:noreply, assign(socket, idle_percentage: idle_percentage)}
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

  def handle_event(
        "rename",
        %{"rename" => %{"name" => new_nick}},
        %Socket{assigns: %{room_pid: room, uid: uid}} = socket
      ) do
    case Room.rename(room, uid, new_nick) do
      :ok ->
        {
          :noreply,
          socket
          |> assign(nick: new_nick, show_info: false, idle_percentage: 0)
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
        %{"message" => %{"text" => text}},
        %Socket{assigns: %{room_pid: room, uid: uid}} = socket
      ) do
    Room.say(room, uid, text)

    {
      :noreply,
      socket
      |> assign(idle_percentage: 0)
      |> clear_flash()
    }
  end

  def handle_event(
        "send_attachment",
        _params,
        %Socket{
          assigns: %{
            room_pid: room,
            uid: uid,
            uploading: false,
            attachment: {_, name, _, data}
          }
        } = socket
      ) do
    case name do
      nil -> Room.flaunt(room, uid, data)
      _ -> Room.attach(room, uid, name, data)
    end

    {
      :noreply,
      socket
      |> assign(idle_percentage: 0, input_mode: :text, attachment: nil)
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

  def handle_event("attach", %{"size" => size}, socket) when size > 10_000_000 do
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
      |> assign(attachment: {size, name, 0, []}, preview_url: url, uploading: true)
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
      |> assign(attachment: {size, nil, 0, []}, preview_url: url, uploading: true)
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

  defp fetch_locale(%{"language" => language}) do
    case language |> language_to_locale() |> validate_locale() do
      nil -> :ok
      locale -> Gettext.put_locale(GaraWeb.Gettext, locale)
    end
  end

  defp fetch_locale(_), do: Gettext.put_locale(GaraWeb.Gettext, "en")

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

  defp fetch_token(%{"token" => token}, room_name) do
    case Guardian.decode_token(token) do
      {id, ^room_name} -> id
      _ -> nil
    end
  end

  defp fetch_token(_, _), do: nil

  defp fetch_preferred_nick(%{"preferred_nick" => nick}), do: nick
  defp fetch_preferred_nick(_), do: nil

  defp accept_chunk(
         %Socket{assigns: %{attachment: {size, name, offset, data}}} = socket,
         chunk
       ) do
    chunk = Base.decode64!(chunk)
    offset = offset + byte_size(chunk)

    cond do
      offset > size ->
        raise("Excessive data received in streaming")

      offset == size ->
        assign(socket,
          attachment: {size, name, offset, Enum.reverse([chunk | data])},
          uploading: false
        )

      true ->
        socket
        |> assign(attachment: {size, name, offset, [chunk | data]})
        |> push_event("read_attachment", %{offset: offset})
    end
  end
end
