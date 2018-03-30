defmodule ETSTest do
  use ExUnit.Case

  setup _context do
    {:ok, hammer_ets_pid} = Hammer.Backend.ETS.start_link()
    {:ok, [pid: hammer_ets_pid]}
  end

  test "count_hit", context do
    pid = context[:pid]
    {stamp, key} = Hammer.Utils.stamp_key("one", 200_000)
    assert {:ok, 1} = Hammer.Backend.ETS.count_hit(pid, key, stamp)
    assert {:ok, 2} = Hammer.Backend.ETS.count_hit(pid, key, stamp)
    assert {:ok, 3} = Hammer.Backend.ETS.count_hit(pid, key, stamp)
  end

  test "get_bucket", context do
    pid = context[:pid]
    {stamp, key} = Hammer.Utils.stamp_key("two", 200_000)
    # With no hits
    assert {:ok, nil} = Hammer.Backend.ETS.get_bucket(pid, key)
    # With one hit
    assert {:ok, 1} = Hammer.Backend.ETS.count_hit(pid, key, stamp)
    assert {:ok, {{_, "two"}, 1, _, _}} = Hammer.Backend.ETS.get_bucket(pid, key)
    # With two hits
    assert {:ok, 2} = Hammer.Backend.ETS.count_hit(pid, key, stamp)
    assert {:ok, {{_, "two"}, 2, _, _}} = Hammer.Backend.ETS.get_bucket(pid, key)
  end

  test "delete_buckets", context do
    pid = context[:pid]
    {stamp, key} = Hammer.Utils.stamp_key("three", 200_000)
    # With no hits
    assert {:ok, 0} = Hammer.Backend.ETS.delete_buckets(pid, "three")
    # With three hits in same bucket
    assert {:ok, 1} = Hammer.Backend.ETS.count_hit(pid, key, stamp)
    assert {:ok, 2} = Hammer.Backend.ETS.count_hit(pid, key, stamp)
    assert {:ok, 3} = Hammer.Backend.ETS.count_hit(pid, key, stamp)
    assert {:ok, 1} = Hammer.Backend.ETS.delete_buckets(pid, "three")
  end
end
