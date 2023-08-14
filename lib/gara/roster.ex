defmodule Gara.Roster do
  @moduledoc """
  Manage a roster of people
  """

  alias Gara.{Defaults, Participant}

  @syllable_head ["b", "p", "m", "f", "t", "d", "n", "l", "g", "h", "r", "c", "s"]
  @syllable_core ["a", "e", "i", "o", "u"]
  @syllable_tail ["s", "n", "m", "l", "r"]

  defstruct next_id: 0,
            name_map: %{},
            info_map: %{}

  @doc """
  Generate a default nick name that is simple to spell and pronounce
  """
  def gen_nick() do
    {hh, hc, ht, th, tc} =
      {Enum.random(@syllable_head), Enum.random(@syllable_core), Enum.random(@syllable_tail),
       Enum.random(@syllable_head), Enum.random(@syllable_core)}

    cond do
      ht == th || hc > tc -> hh <> hc <> th <> tc <> ht
      true -> hh <> hc <> ht <> th <> tc
    end
  end

  @doc """
  get the name of the id, return nil if not found
  """
  def get_name(%__MODULE__{name_map: names}, id), do: names[id]

  @doc """
  count the occupants
  """
  def size(%__MODULE__{info_map: infos}), do: map_size(infos)

  @doc """
  count the occupants, active and past
  """
  def fullsize(%__MODULE__{name_map: names}), do: map_size(names)

  defp join(
         %__MODULE__{next_id: id, name_map: names, info_map: infos} = roster,
         pid,
         preferred_nick
       ) do
    cond do
      map_size(infos) >= Defaults.default(:room_capacity) ->
        {:error, :system_limit}

      true ->
        list = Map.values(names)

        nick =
          cond do
            preferred_nick == nil -> gen_new_nick(list)
            Enum.member?(list, preferred_nick) -> gen_new_nick(list)
            legal_nick?(preferred_nick) -> preferred_nick
            true -> gen_new_nick(list)
          end

        {id,
         %{
           roster
           | next_id: id + 1,
             name_map: Map.put_new(names, id, nick),
             info_map: Map.put_new(infos, id, Participant.new(pid))
         }}
    end
  end

  @doc """
  Rejoin the roster to replace the id. return the {new_id, new_roster}, or {:error, reason}
  """
  def rejoin(
        %__MODULE__{info_map: infos} = roster,
        pid,
        id,
        preferred_nick \\ nil,
        locked? \\ false
      ) do
    case Map.get(infos, id) do
      nil ->
        if locked? do
          {:error, :system_limit}
        else
          join(roster, pid, preferred_nick)
        end

      %Participant{pid: old_pid} ->
        send(old_pid, :hangup)
        {id, put_in(roster[:info_map][id], Participant.renew(pid))}
    end
  end

  @doc """
  leave the roster, return new_roster
  """
  def leave(%__MODULE__{info_map: infos} = roster, id) do
    %{roster | info_map: Map.delete(infos, id)}
  end

  @doc """
  rename one people. return {:ok, new_roster, old_nick} if success, :error if something wrong
  """
  def rename(%__MODULE__{name_map: names} = roster, id, name) do
    case ping(roster, id) do
      :error ->
        {:error, :enodev}

      {:ok, roster} ->
        cond do
          name == names[id] -> {:ok, roster, name}
          names |> Map.values() |> Enum.member?(name) -> {:error, :eexist}
          !legal_nick?(name) -> {:error, :einval}
          true -> {:ok, %{roster | name_map: %{names | id => name}}, names[id]}
        end
    end
  end

  @doc """
  reset idle counter to 0. return {:ok, new_roster} if success, :error if not found
  """
  def ping(%__MODULE__{info_map: infos} = roster, id) do
    case Map.get(infos, id) do
      nil -> :error
      info -> {:ok, put_in(roster[:info_map][id], Participant.clear_idle_counter(info))}
    end
  end

  @doc """
  increment idle counter across the board, if anyone over the limit, force it to leave
  """
  def tick(%__MODULE__{info_map: infos} = roster) do
    idle_limit = Defaults.default(:idle_limit)

    new_infos =
      Enum.flat_map(infos, fn {id, info} ->
        cond do
          info.idle_counter >= idle_limit ->
            send(info.pid, :hangup)
            []

          true ->
            info = Participant.inc_idle_counter(info)
            send(info.pid, {:tick, idle_percentage(info)})
            [{id, info}]
        end
      end)

    %{roster | info_map: Map.new(new_infos)}
  end

  @doc """
  broadcast a message to every one, return :ok
  """
  def broadcast(%__MODULE__{info_map: infos}, msg) do
    Enum.each(infos, fn {_id, info} -> send(info.pid, msg) end)
  end

  @doc """
  unicast a message to a recipient, return :ok
  """
  def unicast(%__MODULE__{name_map: names, info_map: infos}, recipient, msg) do
    Enum.each(infos, fn {id, info} ->
      case names[id] do
        ^recipient -> send(info.pid, msg)
        _ -> :ok
      end
    end)
  end

  @doc """
  Return all active nicks on the roster
  """
  def participants(%__MODULE__{info_map: infos, name_map: names}) do
    Enum.map(infos, fn {id, _} -> names[id] end)
  end

  @doc """
  return the idle_percentage of this id
  """
  def idle_percentage(%__MODULE__{info_map: infos}, id) do
    case Map.get(infos, id) do
      nil -> 0
      info -> idle_percentage(info)
    end
  end

  defp idle_percentage(info) do
    Float.floor(info.idle_counter / Defaults.default(:idle_limit) * 100)
  end

  defp gen_new_nick(list) do
    nick = gen_nick()

    case Enum.member?(list, nick) do
      true -> gen_new_nick(list)
      false -> nick
    end
  end

  defp legal_nick?(nick) do
    cond do
      nick == "" -> false
      byte_size(nick) > 24 -> false
      String.match?(nick, ~r/[[:punct:][:space:][:cntrl:]]+/u) -> false
      true -> true
    end
  end
end
