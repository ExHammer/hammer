defmodule Hammer.Backend.ETSTest do
  use ExUnit.Case

  test "pruning" do
    start_supervised!({Hammer.Backend.ETS, cleanup_interval_ms: 100})
    Hammer.check_rate("something-pruned", _scale_ms = 100, _limit = 10)

    assert [{{"something-pruned", _bucket}, _count = 1, expires_at}] =
             :ets.tab2list(:hammer_ets_buckets)

    assert expires_at > System.system_time(:millisecond)
    assert expires_at < System.system_time(:millisecond) + 100

    :timer.sleep(_ms = 200)

    assert :ets.tab2list(:hammer_ets_buckets) == []
  end
end
