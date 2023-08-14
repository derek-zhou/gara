defmodule Gara.Participant do
  alias Gara.Defaults

  defstruct pid: nil, idle_counter: 0, want_locked?: false

  def renew(pid), do: %__MODULE__{pid: pid}

  def new(pid), do: %__MODULE__{pid: pid, idle_counter: Defaults.default(:init_idle)}

  def lock(p), do: %{p | want_locked?: true}

  def unlock(p), do: %{p | want_locked?: false}

  def clear_idle_counter(p), do: %{p | idle_counter: 0}

  def inc_idle_counter(p), do: %{p | idle_counter: p.idle_counter + 1}
end
