defmodule HammerTest do
  use ExUnit.Case, async: true

  setup _context do
    {:ok, _hammer_ets_pid} = Hammer.Backend.ETS.start_link()
    {:ok, hammer_pid} = Hammer.start_link(backend: Hammer.Backend.ETS)
    {:ok, hammer_server: hammer_pid}
  end

  test "make_rate_checker" do
    check = Hammer.make_rate_checker("some-prefix:", 10000, 2)
    assert {:allow, 1} = check.("aaa")
    assert {:allow, 2} = check.("aaa")
    assert {:deny,  2} = check.("aaa")
    assert {:deny,  2} = check.("aaa")
    assert {:allow, 1} = check.("bbb")
    assert {:allow, 2} = check.("bbb")
    assert {:deny,  2} = check.("bbb")
    assert {:deny,  2} = check.("bbb")
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
    :timer.sleep 1001
    assert {:allow, 1} = Hammer.check_rate("my-bucket", 1000, 2)
    assert {:allow, 2} = Hammer.check_rate("my-bucket", 1000, 2)
    assert {:deny, 2} = Hammer.check_rate("my-bucket", 1000, 2)
  end

  test "returns expected tuples on inspect_bucket" do
    assert {0, 2, _, nil, nil} = Hammer.inspect_bucket("my-bucket1", 1000, 2)
    assert {:allow, 1} = Hammer.check_rate("my-bucket1", 1000, 2)
    assert {1, 1, _, _, _} = Hammer.inspect_bucket("my-bucket1", 1000, 2)
    assert {:allow, 2} = Hammer.check_rate("my-bucket1", 1000, 2)
    assert {:allow, 1} = Hammer.check_rate("my-bucket2", 1000, 2)
    assert {2, 0, _, _, _} = Hammer.inspect_bucket("my-bucket1", 1000, 2)
    assert {:deny, 2} = Hammer.check_rate("my-bucket1", 1000, 2)
    assert {3, 0, ms_to_next_bucket, _, _} = Hammer.inspect_bucket("my-bucket1", 1000, 2)
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


defmodule UtilsTest do
  use ExUnit.Case
  doctest Hammer.Utils

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

end
