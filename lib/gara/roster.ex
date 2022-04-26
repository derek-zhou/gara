defmodule Gara.Roster do
  @moduledoc """
  Manage a roster of people
  """

  alias Gara.Defaults

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

  @doc """
  Join the roster. return the {new_id, new_roster}, or {:error, reason}
  """
  def join(
        %__MODULE__{next_id: id, name_map: names, info_map: infos} = roster,
        pid,
        preferred_nick \\ nil
      ) do
    idle_counter = Defaults.default(:init_idle)

    cond do
      map_size(infos) >= Defaults.default(:room_capacity) ->
        {:error, :system_limit}

      true ->
        list = Map.values(names)

        nick =
          cond do
            preferred_nick == nil -> gen_new_nick(list)
            Enum.member?(list, preferred_nick) -> gen_new_nick(list)
            true -> preferred_nick
          end

        {id,
         %{
           roster
           | next_id: id + 1,
             name_map: Map.put_new(names, id, nick),
             info_map: Map.put_new(infos, id, {pid, idle_counter})
         }}
    end
  end

  @doc """
  Rejoin the roster to replace the id. return the {new_id, new_roster}, or {:error, reason}
  """
  def rejoin(%__MODULE__{info_map: infos} = roster, pid, id, preferred_nick \\ nil) do
    case Map.get(infos, id) do
      nil ->
        join(roster, pid, preferred_nick)

      {old_pid, _} ->
        send(old_pid, :hangup)
        {id, %{roster | info_map: %{infos | id => {pid, 0}}}}
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
        :error

      {:ok, roster} ->
        cond do
          name == names[id] -> {:ok, roster, name}
          names |> Map.values() |> Enum.member?(name) -> :error
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
      {pid, _} -> {:ok, %{roster | info_map: %{infos | id => {pid, 0}}}}
    end
  end

  @doc """
  increment idle counter across the board, if anyone over the limit, force it to leave
  """
  def tick(%__MODULE__{info_map: infos} = roster) do
    idle_limit = Defaults.default(:idle_limit)

    new_infos =
      Enum.flat_map(infos, fn {id, {pid, idle_counter}} ->
        cond do
          idle_counter >= idle_limit ->
            send(pid, :hangup)
            []

          true ->
            idle_counter = idle_counter + 1
            send(pid, {:tick, Float.floor(idle_counter / idle_limit * 100)})
            [{id, {pid, idle_counter}}]
        end
      end)

    %{roster | info_map: Map.new(new_infos)}
  end

  @doc """
  broadcast a message to every one, return :ok
  """
  def broadcast(%__MODULE__{info_map: infos}, msg) do
    Enum.each(infos, fn {_id, {pid, _}} -> send(pid, msg) end)
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
    idle_limit = Defaults.default(:idle_limit)

    case Map.get(infos, id) do
      nil -> 0
      {_pid, idle_counter} -> Float.floor(idle_counter / idle_limit * 100)
    end
  end

  defp gen_new_nick(list) do
    nick = gen_nick()

    case Enum.member?(list, nick) do
      true -> gen_new_nick(list)
      false -> nick
    end
  end
end
