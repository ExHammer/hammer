defmodule Hammer.CleanTestHelpers do
  @moduledoc false

  import ExUnit.Assertions

  def eventually(fun, timeout \\ 5000, interval \\ 50) do
    eventually(fun, timeout, interval, System.monotonic_time(:millisecond))
  end

  defp eventually(fun, timeout, interval, start_time) do
    if fun.() do
      :ok
    else
      now = System.monotonic_time(:millisecond)

      if now - start_time > timeout do
        flunk("Condition not met within #{timeout}ms")
      else
        Process.sleep(interval)
        eventually(fun, timeout, interval, start_time)
      end
    end
  end
end

defmodule Hammer.CallbackHandler do
  @moduledoc false

  def handle(algorithm, entries, extra) do
    send(extra, {:before_clean_mfa, algorithm, entries})
  end
end
