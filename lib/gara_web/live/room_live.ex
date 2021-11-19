defmodule GaraWeb.RoomLive do
  use Surface.LiveView
  import GaraWeb.Gettext
  require Logger

  alias Gara.{Room, Rooms, Message}
  alias Phoenix.LiveView.Socket
  alias GaraWeb.{Main, Header, Chat, Guardian}

  # client side state
  data tz_offset, :integer, default: 0

  # states
  data room_name, :string, default: ""
  data room_pid, :pid, default: nil
  data room_stat, :map, default: nil
  data participants, :list, default: []
  # :unkoown, :existed, :joined or :hangup
  data room_status, :atom, default: :unknown
  data nick, :string, default: ""
  data uid, :integer, default: 0
  data idle_percentage, :integer, default: 0

  # temporary state
  data messages, :list, default: []

  # for GUI
  data show_roster, :boolean, default: false
  data show_info, :boolean, default: false

  def mount(%{"name" => room_name}, _session, %Socket{assigns: %{live_action: :chat}} = socket) do
    socket = assign(socket, room_name: room_name)

    socket =
      case Registry.lookup(Rooms, room_name) do
        [] ->
          cond do
            connected?(socket) ->
              socket
              |> put_flash(:error, gettext("Room closed already"))
              |> assign(page_title: "Room closed already")
              |> push_event("leave", %{})

            true ->
              raise(GaraWeb.RoomNotFoundError, gettext("No such room"))
              socket
          end

        [{pid, _}] ->
          stat = Room.stat(pid)

          socket =
            assign(socket,
              room_pid: pid,
              room_stat: stat,
              page_title: stat.topic,
              room_status: :existed
            )

          cond do
            connected?(socket) ->
              values = get_connect_params(socket)
              socket = fetch_tz_offset(socket, values)
              old_id = fetch_token(values, room_name)
              fetch_locale(values)
              Process.monitor(pid)

              case Room.join(pid, old_id) do
                {:error, _} ->
                  socket
                  |> put_flash(:error, gettext("No space in room"))
                  |> push_event("leave", %{})

                {^old_id, nick, participants, messages} ->
                  socket
                  |> assign(
                    uid: old_id,
                    nick: nick,
                    room_status: :joined,
                    participants: participants,
                    messages: messages
                  )
                  |> assign(page_title: "Room closed already")
                  |> put_flash(:info, gettext("Welcome back, ") <> nick)

                {id, nick, participants, messages} ->
                  {:ok, token} = Guardian.build_token(id, room_name)

                  socket
                  |> assign(
                    uid: id,
                    nick: nick,
                    room_status: :joined,
                    participants: participants,
                    messages: messages
                  )
                  |> push_event("set_value", %{key: "token", value: token})
                  |> put_flash(
                    :info,
                    gettext("Your temporary nickname is: ") <>
                      nick <>
                      ". " <>
                      gettext("You should change it by clicking the top right corner")
                  )
              end

            true ->
              socket
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

  def handle_info({:tick, idle_counter, idle_limit}, socket) do
    {:noreply, assign(socket, idle_percentage: Float.floor(idle_counter / idle_limit * 100))}
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

  def handle_info(
        {:leave_message, _mid, _ts, nick} = message,
        %Socket{assigns: %{participants: participants}} = socket
      ) do
    participants = Enum.reject(participants, &(&1 == nick))
    {:noreply, assign(socket, messages: [message], participants: participants)}
  end

  def handle_info(
        {:join_message, _mid, _ts, nick} = message,
        %Socket{assigns: %{participants: participants}} = socket
      ) do
    participants = Enum.reject(participants, &(&1 == nick))
    participants = [nick | participants]
    {:noreply, assign(socket, messages: [message], participants: participants)}
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
      |> assign(room_status: :hangup, show_info: false, show_roster: false)
      |> put_flash(:info, gettext("You left"))
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
        {:noreply, assign(socket, nick: new_nick, show_info: false)}

      :error ->
        {:noreply, put_flash(socket, :error, gettext("The nickname is taken."))}
    end
  end

  def handle_event(
        "message",
        %{"message" => %{"text" => text}},
        %Socket{assigns: %{room_pid: room, uid: uid}} = socket
      ) do
    Room.say(room, uid, Message.parse(text))
    {:noreply, socket}
  end

  def handle_event("click_topic", _, %Socket{assigns: %{show_roster: true}} = socket) do
    {:noreply, assign(socket, show_roster: false)}
  end

  def handle_event("click_topic", _, %Socket{assigns: %{show_roster: false}} = socket) do
    {:noreply, assign(socket, show_roster: true, show_info: false)}
  end

  def handle_event("click_nick", _, %Socket{assigns: %{show_info: true}} = socket) do
    {:noreply, assign(socket, show_info: false)}
  end

  def handle_event("click_nick", _, %Socket{assigns: %{show_info: false}} = socket) do
    {:noreply, assign(socket, show_info: true, show_roster: false)}
  end

  def handle_event("click_else", _, socket) do
    {:noreply, assign(socket, show_info: false, show_roster: false)}
  end

  defp fetch_tz_offset(socket, %{"timezoneOffset" => offset}) do
    assign(socket, tz_offset: offset)
  end

  defp fetch_tz_offset(socket, _), do: socket

  defp fetch_locale(%{"language" => locale}), do: Gettext.put_locale(LivWeb.Gettext, locale)
  defp fetch_locale(_), do: Gettext.put_locale(LivWeb.Gettext, "en")

  defp fetch_token(%{"token" => token}, room_name) do
    case Guardian.decode_token(token) do
      {id, ^room_name} -> id
      _ -> nil
    end
  end

  defp fetch_token(_, _), do: nil
end
