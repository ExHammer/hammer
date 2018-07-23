defmodule ETSTest do
  use ExUnit.Case

  setup _context do
    Application.stop(:hammer)

    Application.put_env(
      :hammer,
      :backend,
      {Hammer.Backend.ETS, [expiry_ms: 5, cleanup_interval_ms: 2]}
    )

    {:ok, [app: Application.ensure_all_started(:hammer)]}
  end

  test "count_hit", _context do
    {stamp, key} = Hammer.Utils.stamp_key("one", 200_000)
    assert {:ok, 1} = Hammer.Backend.ETS.count_hit(key, stamp)
    assert {:ok, 2} = Hammer.Backend.ETS.count_hit(key, stamp)
    assert {:ok, 3} = Hammer.Backend.ETS.count_hit(key, stamp)
  end

  test "get_bucket", _context do
    {stamp, key} = Hammer.Utils.stamp_key("two", 200_000)
    # With no hits
    assert {:ok, nil} = Hammer.Backend.ETS.get_bucket(key)
    # With one hit
    assert {:ok, 1} = Hammer.Backend.ETS.count_hit(key, stamp)
    assert {:ok, {{_, "two"}, 1, _, _}} = Hammer.Backend.ETS.get_bucket(key)
    # With two hits
    assert {:ok, 2} = Hammer.Backend.ETS.count_hit(key, stamp)
    assert {:ok, {{_, "two"}, 2, _, _}} = Hammer.Backend.ETS.get_bucket(key)
  end

  test "delete_buckets", _context do
    {stamp, key} = Hammer.Utils.stamp_key("three", 200_000)
    # With no hits
    assert {:ok, 0} = Hammer.Backend.ETS.delete_buckets("three")
    # With three hits in same bucket
    assert {:ok, 1} = Hammer.Backend.ETS.count_hit(key, stamp)
    assert {:ok, 2} = Hammer.Backend.ETS.count_hit(key, stamp)
    assert {:ok, 3} = Hammer.Backend.ETS.count_hit(key, stamp)
    assert {:ok, 1} = Hammer.Backend.ETS.delete_buckets("three")
  end

  test "timeout pruning", _context do
    {_, context} = Application.get_env(:hammer, :backend)
    expiry_ms = context[:expiry_ms]
    {stamp, key} = Hammer.Utils.stamp_key("one", 200_000)
    assert {:ok, 1} = Hammer.Backend.ETS.count_hit(key, stamp)
    assert {:ok, {{_, "one"}, 1, _, _}} = Hammer.Backend.ETS.get_bucket(key)
    :timer.sleep(expiry_ms * 2)
    assert {:ok, nil} = Hammer.Backend.ETS.get_bucket(key)
  end
end
