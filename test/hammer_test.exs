defmodule HammerTest do
  use ExUnit.Case, async: true

  setup _context do
    {:ok, _hammer_ets_pid} = Hammer.Backend.ETS.start_link()
    {:ok, []}
  end

  test "make_rate_checker" do
    check = Hammer.make_rate_checker("some-prefix:", 10000, 2)
    assert {:allow, 1} = check.("aaa")
    assert {:allow, 2} = check.("aaa")
    assert {:deny, 2} = check.("aaa")
    assert {:deny, 2} = check.("aaa")
    assert {:allow, 1} = check.("bbb")
    assert {:allow, 2} = check.("bbb")
    assert {:deny, 2} = check.("bbb")
    assert {:deny, 2} = check.("bbb")
  end

  test "returns {:ok, 1} tuple on first access" do
    assert {:allow, 1} = Hammer.check_rate("my-bucket", 10_000, 10)
  end

  test "returns {:ok, 4} tuple on in-limit checks" do
    assert {:allow, 1} = Hammer.check_rate("my-bucket", 10_000, 10)
    assert {:allow, 2} = Hammer.check_rate("my-bucket", 10_000, 10)
    assert {:allow, 3} = Hammer.check_rate("my-bucket", 10_000, 10)
    assert {:allow, 4} = Hammer.check_rate("my-bucket", 10_000, 10)
  end

  test "returns expected tuples on mix of in-limit and out-of-limit checks" do
    assert {:allow, 1} = Hammer.check_rate("my-bucket", 10_000, 2)
    assert {:allow, 2} = Hammer.check_rate("my-bucket", 10_000, 2)
    assert {:deny, 2} = Hammer.check_rate("my-bucket", 10_000, 2)
    assert {:deny, 2} = Hammer.check_rate("my-bucket", 10_000, 2)
  end

  test "returns expected tuples on 1000ms bucket check with a sleep in the middle" do
    assert {:allow, 1} = Hammer.check_rate("my-bucket", 1000, 2)
    assert {:allow, 2} = Hammer.check_rate("my-bucket", 1000, 2)
    assert {:deny, 2} = Hammer.check_rate("my-bucket", 1000, 2)
    :timer.sleep(1001)
    assert {:allow, 1} = Hammer.check_rate("my-bucket", 1000, 2)
    assert {:allow, 2} = Hammer.check_rate("my-bucket", 1000, 2)
    assert {:deny, 2} = Hammer.check_rate("my-bucket", 1000, 2)
  end

  test "returns expected tuples on inspect_bucket" do
    assert {:ok, {0, 2, _, nil, nil}} = Hammer.inspect_bucket("my-bucket1", 1000, 2)
    assert {:allow, 1} = Hammer.check_rate("my-bucket1", 1000, 2)
    assert {:ok, {1, 1, _, _, _}} = Hammer.inspect_bucket("my-bucket1", 1000, 2)
    assert {:allow, 2} = Hammer.check_rate("my-bucket1", 1000, 2)
    assert {:allow, 1} = Hammer.check_rate("my-bucket2", 1000, 2)
    assert {:ok, {2, 0, _, _, _}} = Hammer.inspect_bucket("my-bucket1", 1000, 2)
    assert {:deny, 2} = Hammer.check_rate("my-bucket1", 1000, 2)
    assert {:ok, {3, 0, ms_to_next_bucket, _, _}} = Hammer.inspect_bucket("my-bucket1", 1000, 2)
    assert ms_to_next_bucket < 1000
  end

  test "returns expected tuples on delete_buckets" do
    assert {:allow, 1} = Hammer.check_rate("my-bucket1", 1000, 2)
    assert {:allow, 2} = Hammer.check_rate("my-bucket1", 1000, 2)
    assert {:deny, 2} = Hammer.check_rate("my-bucket1", 1000, 2)
    assert {:allow, 1} = Hammer.check_rate("my-bucket2", 1000, 2)
    assert {:allow, 2} = Hammer.check_rate("my-bucket2", 1000, 2)
    assert {:deny, 2} = Hammer.check_rate("my-bucket2", 1000, 2)
    assert {:ok, 1} = Hammer.delete_buckets("my-bucket1")
    assert {:allow, 1} = Hammer.check_rate("my-bucket1", 1000, 2)
    assert {:deny, 2} = Hammer.check_rate("my-bucket2", 1000, 2)

    assert {:ok, 0} = Hammer.delete_buckets("unknown-bucket")
  end
end

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

defmodule UtilsTest do
  use ExUnit.Case

  test "timestamp" do
    assert is_integer(Hammer.Utils.timestamp())
  end

  test "stamp_key" do
    id = "test_one_two"
    {stamp, key} = Hammer.Utils.stamp_key(id, 60_000)
    assert is_integer(stamp)
    assert is_tuple(key)
    {bucket_number, b_id} = key
    assert is_integer(bucket_number)
    assert b_id == id
  end

  test "get_backend_module" do
    # With :single and default backend config
    assert Hammer.Utils.get_backend_module(:single) == Hammer.Backend.ETS
    # With :single and configured backend config
    Application.put_env(:hammer, :backend, {Hammer.Backend.SomeBackend, []})
    assert Hammer.Utils.get_backend_module(:single) == Hammer.Backend.SomeBackend
    # with a specific backend config
    Application.put_env(:hammer, :backend, one: {Hammer.Backend.SomeBackend, []})
    assert Hammer.Utils.get_backend_module(:one) == Hammer.Backend.SomeBackend
  end
end
