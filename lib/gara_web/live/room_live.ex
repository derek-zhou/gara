defmodule GaraWeb.RoomLive do
  use Surface.LiveView
  require Logger

  alias Gara.{Room, Rooms, Defaults, Message}
  alias Phoenix.LiveView.Socket
  alias GaraWeb.Router.Helpers, as: Routes
  alias GaraWeb.{Endpoint, Guardian}

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
  data history, :list, default: []
  data message, :tuple, default: nil

  def mount(%{"name" => room_name}, _session, %Socket{assigns: %{live_action: :chat}} = socket) do
    socket = assign(socket, room_name: room_name)

    socket =
      case Registry.lookup(Rooms, room_name) do
        [] ->
          push_event(socket, "leave", %{reason: "no such room"})

        [{pid, _}] ->
          socket = assign(socket, room_pid: pid, room_stat: Room.stat(pid), room_status: :existed)

          cond do
            connected?(socket) ->
              values = get_connect_params(socket)
              socket = fetch_tz_offset(socket, values)
              fetch_locale(values)
              Process.monitor(pid)

              case Room.join(pid, fetch_token(values, room_name)) do
                :error ->
                  push_event(socket, "leave", %{reason: "no space in room"})

                {id, nick, participants, history} ->
                  {:ok, token} = Guardian.build_token(id, room_name)

                  socket
                  |> assign(
                    uid: id,
                    nick: nick,
                    room_status: :joined,
                    participants: participants,
                    history: history
                  )
                  |> push_event("set_value", %{key: "token", value: token})
              end

            true ->
              socket
          end
      end

    {:ok, socket, temporary_assigns: [history: [], message: nil]}
  end

  def handle_info(:hangup, socket) do
    {
      :noreply,
      socket
      |> assign(room_status: :hangup)
      |> push_event("leave", %{reason: "server hangup"})
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
      |> push_event("leave", %{reason: "server crashed"})
    }
  end

  def handle_info({:user_message, _, _, _} = message, socket) do
    {:noreply, assign(socket, message: message)}
  end

  def handle_info(
        {:leave_message, nick} = message,
        %Socket{assigns: %{participants: participants}} = socket
      ) do
    participants = Enum.reject(participants, &(&1 == nick))
    {:noreply, assign(socket, message: message, participants: participants)}
  end

  def handle_info(
        {:join_message, nick} = message,
        %Socket{assigns: %{participants: participants}} = socket
      ) do
    participants = [nick | participants]
    {:noreply, assign(socket, message: message, participants: participants)}
  end

  def handle_info(
        {:rename_message, old_nick, new_nick} = message,
        %Socket{assigns: %{participants: participants, nick: nick}} = socket
      ) do
    participants = Enum.reject(participants, &(&1 == old_nick))
    participants = [new_nick | participants]

    nick =
      case old_nick do
        ^nick -> new_nick
        _ -> nick
      end

    {:noreply, assign(socket, message: message, participants: participants, nick: nick)}
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
