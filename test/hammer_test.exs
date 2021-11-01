defmodule HammerTest do
  use ExUnit.Case, async: false

  setup _context do
    pool = Hammer.Utils.pool_name()

    opts = [
      name: {:local, pool},
      worker_module: Hammer.Backend.Redis,
      size: 4,
      max_overflow: 4
    ]

    worker_args = [
      expiry_ms: 5001,
      cleanup_interval_ms: 6002
    ]

    case :poolboy.start_link(opts, worker_args) do
      {:ok, _pid} -> nil
      {:error, {:already_started, _pid}} -> nil
    end

    {:ok, [pool: pool]}
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
    assert {:allow, 1} = Hammer.check_rate("first-access-bucket", 10_000, 10)
  end

  test "returns {:ok, 4} tuple on in-limit checks" do
    assert {:allow, 1} = Hammer.check_rate("limit-check-bucket", 10_000, 10)
    assert {:allow, 2} = Hammer.check_rate("limit-check-bucket", 10_000, 10)
    assert {:allow, 3} = Hammer.check_rate("limit-check-bucket", 10_000, 10)
    assert {:allow, 4} = Hammer.check_rate("limit-check-bucket", 10_000, 10)
  end

  test "returns expected tuples on mix of in-limit and out-of-limit checks" do
    assert {:allow, 1} = Hammer.check_rate("limit-mix-bucket", 10_000, 2)
    assert {:allow, 2} = Hammer.check_rate("limit-mix-bucket", 10_000, 2)
    assert {:deny, 2} = Hammer.check_rate("limit-mix-bucket", 10_000, 2)
    assert {:deny, 2} = Hammer.check_rate("limit-mix-bucket", 10_000, 2)
  end

  test "returns expected tuples on 1000ms bucket check with a sleep in the middle" do
    assert {:allow, 1} = Hammer.check_rate("sleep-bucket", 1000, 2)
    assert {:allow, 2} = Hammer.check_rate("sleep-bucket", 1000, 2)
    assert {:deny, 2} = Hammer.check_rate("sleep-bucket", 1000, 2)
    :timer.sleep(1001)
    assert {:allow, 1} = Hammer.check_rate("sleep-bucket", 1000, 2)
    assert {:allow, 2} = Hammer.check_rate("sleep-bucket", 1000, 2)
    assert {:deny, 2} = Hammer.check_rate("sleep-bucket", 1000, 2)
  end

  test "returns expected tuples on inspect_bucket" do
    assert {:ok, {0, 2, _, nil, nil}} = Hammer.inspect_bucket("inspect-bucket-a", 1000, 2)
    assert {:allow, 1} = Hammer.check_rate("inspect-bucket-a", 1000, 2)
    assert {:ok, {1, 1, _, _, _}} = Hammer.inspect_bucket("inspect-bucket-a", 1000, 2)
    assert {:allow, 2} = Hammer.check_rate("inspect-bucket-a", 1000, 2)
    assert {:allow, 1} = Hammer.check_rate("inspect-bucket-b", 1000, 2)
    assert {:ok, {2, 0, _, _, _}} = Hammer.inspect_bucket("inspect-bucket-a", 1000, 2)
    assert {:deny, 2} = Hammer.check_rate("inspect-bucket-a", 1000, 2)
    assert {:ok, {3, 0, ms_to_next_bucket, _, _}} = Hammer.inspect_bucket("inspect-bucket-a", 1000, 2)
    assert ms_to_next_bucket < 1000
  end

  test "returns expected tuples on delete_buckets" do
    assert {:allow, 1} = Hammer.check_rate("delete-bucket-a", 1000, 2)
    assert {:allow, 2} = Hammer.check_rate("delete-bucket-a", 1000, 2)
    assert {:deny, 2} = Hammer.check_rate("delete-bucket-a", 1000, 2)
    assert {:allow, 1} = Hammer.check_rate("delete-bucket-b", 1000, 2)
    assert {:allow, 2} = Hammer.check_rate("delete-bucket-b", 1000, 2)
    assert {:deny, 2} = Hammer.check_rate("delete-bucket-b", 1000, 2)
    assert {:ok, 1} = Hammer.delete_buckets("delete-bucket-a")
    assert {:allow, 1} = Hammer.check_rate("delete-bucket-a", 1000, 2)
    assert {:deny, 2} = Hammer.check_rate("delete-bucket-b", 1000, 2)

    assert {:ok, 0} = Hammer.delete_buckets("unknown-bucket")
  end

  test "count_hit_inc" do
    assert {:allow, 4} = Hammer.check_rate_inc("count-bucket", 1000, 10, 4)
    assert {:allow, 9} = Hammer.check_rate_inc("count-bucket", 1000, 10, 5)
    assert {:deny, 10} = Hammer.check_rate_inc("count-bucket", 1000, 10, 3)
  end

  test "mixing count_hit with count_hit_inc" do
    assert {:allow, 3} = Hammer.check_rate_inc("mix-count-bucket", 1000, 10, 3)
    assert {:allow, 4} = Hammer.check_rate("mix-count-bucket", 1000, 10)
    assert {:allow, 5} = Hammer.check_rate("mix-count-bucket", 1000, 10)
    assert {:allow, 9} = Hammer.check_rate_inc("mix-count-bucket", 1000, 10, 4)
    assert {:allow, 10} = Hammer.check_rate("mix-count-bucket", 1000, 10)
    assert {:deny, 10} = Hammer.check_rate_inc("mix-count-bucket", 1000, 10, 2)
  end
end
