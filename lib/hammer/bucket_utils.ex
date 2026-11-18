defmodule Hammer.BucketUtils do
  @moduledoc false

  @doc """
  Milliseconds until a leaky bucket that counts in whole seconds has leaked
  `excess` more, given `now` in seconds.

  The leak lands when the wall clock reaches second `now + seconds`, so the
  wait runs to that boundary rather than a full `seconds * 1000`. For a hit
  the bucket can hold at all, sleeping it is always sufficient; a cost larger
  than the capacity is never allowed, whatever the wait.

  A rate of 0 never leaks. There is no honest wait to report, so the flat
  second these buckets always answered with is kept.
  """
  @spec leak_wait(now :: integer(), excess :: pos_integer(), leak_rate :: number()) ::
          pos_integer()
  def leak_wait(now, excess, leak_rate) when leak_rate > 0 do
    seconds = ceil(excess / leak_rate)
    max((now + seconds) * 1000 - System.system_time(:millisecond), 1)
  end

  def leak_wait(_now, _excess, _leak_rate), do: 1000
end
