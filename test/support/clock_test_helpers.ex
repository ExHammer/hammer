defmodule Hammer.ClockTestHelpers do
  @moduledoc false

  @doc """
  Blocks until the wall clock is in the first 800ms of a second.

  The whole-second bucket algorithms read `System.system_time(:second)`, so a
  test that seeds a bucket and then hits it gets a different answer if the
  second rolls over in between. Calling this first leaves at least 200ms of
  headroom for work that takes microseconds.
  """
  @spec await_fresh_second() :: :ok
  def await_fresh_second do
    into_second = rem(System.system_time(:millisecond), 1000)
    if into_second > 800, do: Process.sleep(1001 - into_second)
    :ok
  end
end
