defmodule Gara.Roster do
  @moduledoc """
  Manage a roster of people
  """

  alias Gara.Defaults

  @syllable_head ["b", "p", "m", "f", "t", "d", "n", "l", "g", "h", "r", "c", "s"]
  @syllable_core ["a", "e", "i", "o", "u"]
  @syllable_tail ["s", "n", "m", "l", "r"]

  # this struct has maps and sets all keyed off the same opaque index from monitor
  # all names ever exists in the rosters. Names shall not be reused
  defstruct name_map: %{},
            # all participants that have voted to lock the room.
            lock_set: nil,
            # all participants that currently are connected
            pid_map: %{}

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
  count the occupants, active and past
  """
  def full_size(%__MODULE__{name_map: names}), do: map_size(names)

  @doc """
  count the occupants, active only
  """
  def size(%__MODULE__{pid_map: pids}), do: map_size(pids)

  @doc """
  poll the consensus of locking, if all voted to change return true, otherwise, false
  """
  def poll(%__MODULE__{pid_map: pids, lock_set: locks}, locked?) do
    Enum.all?(pids, fn {id, _} -> MapSet.member?(locks, id) != locked? end)
  end

  @doc """
  make a new roster
  """
  def new(), do: %__MODULE__{lock_set: MapSet.new()}

  defp join(
         %__MODULE__{name_map: names, pid_map: pids} = roster,
         pid,
         preferred_nick
       ) do
    cond do
      map_size(pids) >= Defaults.default(:room_capacity) ->
        {:error, :system_limit}

      true ->
        id = Process.monitor(pid)
        list = Map.values(names)

        nick =
          cond do
            preferred_nick == nil -> gen_new_nick(list)
            Enum.member?(list, preferred_nick) -> gen_new_nick(list)
            legal_nick?(preferred_nick) -> preferred_nick
            true -> gen_new_nick(list)
          end

        {id,
         %{roster | name_map: Map.put_new(names, id, nick), pid_map: Map.put_new(pids, id, pid)}}
    end
  end

  @doc """
  Rejoin the roster to replace the id. return the {new_id, new_roster}, or {:error, reason}
  """
  def rejoin(
        %__MODULE__{name_map: names, pid_map: pids, lock_set: locks} = roster,
        pid,
        id,
        preferred_nick \\ nil,
        locked? \\ false
      ) do
    case Map.get(names, id) do
      nil ->
        if locked? do
          {:error, :system_limit}
        else
          join(roster, pid, preferred_nick)
        end

      name ->
        case Map.get(pids, id) do
          nil -> :ok
          old_pid -> send(old_pid, :hangup)
        end

        new_id = Process.monitor(pid)
        names = names |> Map.delete(id) |> Map.put_new(new_id, name)
        # pld_pid is removed at hangup time
        pids = Map.put_new(pids, new_id, pid)

        locks =
          if MapSet.member?(locks, id) do
            locks |> MapSet.delete(id) |> MapSet.put(new_id)
          else
            locks
          end

        {new_id, %__MODULE__{name_map: names, pid_map: pids, lock_set: locks}}
    end
  end

  @doc """
  leave the roster, return new_roster
  """
  def leave(%__MODULE__{pid_map: pids} = roster, id) do
    %{roster | pid_map: Map.delete(pids, id)}
  end

  @doc """
  rename one people. return {:ok, new_roster, old_nick} if success, :error if something wrong
  """
  def rename(%__MODULE__{name_map: names} = roster, id, name) do
    case Map.get(names, id) do
      nil ->
        {:error, :enodev}

      ^name ->
        {:ok, roster, name}

      old_name ->
        cond do
          names |> Map.values() |> Enum.member?(name) -> {:error, :eexist}
          !legal_nick?(name) -> {:error, :einval}
          true -> {:ok, %{roster | name_map: %{names | id => name}}, old_name}
        end
    end
  end

  @doc """
  broadcast a message to every one, return :ok
  """
  def broadcast(%__MODULE__{pid_map: pids}, msg) do
    Enum.each(pids, fn {_id, pid} -> send(pid, msg) end)
  end

  @doc """
  unicast a message to a recipient, return :ok
  """
  def unicast(%__MODULE__{name_map: names, pid_map: pids}, recipient, msg) do
    Enum.each(pids, fn {id, pid} ->
      case names[id] do
        ^recipient -> send(pid, msg)
        _ -> :ok
      end
    end)
  end

  @doc """
  Return all active nicks on the roster
  """
  def participants(%__MODULE__{pid_map: pids, name_map: names}) do
    Enum.map(pids, fn {id, _} -> names[id] end)
  end

  @doc """
  one id votes to lock the room. return roster
  """
  def lock(%__MODULE__{lock_set: locks} = roster, id) do
    %{roster | lock_set: MapSet.put(locks, id)}
  end

  @doc """
  one id votes to unlock the room. return roster
  """
  def unlock(%__MODULE__{lock_set: locks} = roster, id) do
    %{roster | lock_set: MapSet.delete(locks, id)}
  end

  @doc """
  return if one id want to lock the room
  """
  def want_lock?(%__MODULE__{lock_set: locks}, id), do: MapSet.member?(locks, id)

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
