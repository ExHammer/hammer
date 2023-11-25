defmodule HammerTest do
  use ExUnit.Case

  setup do
    start_supervised!({Hammer.Backend.ETS, cleanup_interval_ms: :timer.seconds(60)})
    :ok
  end

  defp bucket, do: "bucket:#{System.unique_integer([:positive])}"

  test "returns {:ok, 1} tuple on first access" do
    assert {:allow, 1} = Hammer.check_rate(bucket(), 10_000, 10)
  end

  test "returns {:ok, 4} tuple on in-limit checks" do
    bucket = bucket()
    assert {:allow, 1} = Hammer.check_rate(bucket, 10_000, 10)
    assert {:allow, 2} = Hammer.check_rate(bucket, 10_000, 10)
    assert {:allow, 3} = Hammer.check_rate(bucket, 10_000, 10)
    assert {:allow, 4} = Hammer.check_rate(bucket, 10_000, 10)
  end

  test "returns expected tuples on mix of in-limit and out-of-limit checks" do
    bucket = bucket()
    assert {:allow, 1} = Hammer.check_rate(bucket, 10_000, 2)
    assert {:allow, 2} = Hammer.check_rate(bucket, 10_000, 2)
    assert {:deny, 2} = Hammer.check_rate(bucket, 10_000, 2)
    assert {:deny, 2} = Hammer.check_rate(bucket, 10_000, 2)
  end

  test "returns expected tuples on 1000ms bucket check with a sleep in the middle" do
    bucket = bucket()
    assert {:allow, 1} = Hammer.check_rate(bucket, 1000, 2)
    assert {:allow, 2} = Hammer.check_rate(bucket, 1000, 2)
    assert {:deny, 2} = Hammer.check_rate(bucket, 1000, 2)
    :timer.sleep(1001)
    assert {:allow, 1} = Hammer.check_rate(bucket, 1000, 2)
    assert {:allow, 2} = Hammer.check_rate(bucket, 1000, 2)
    assert {:deny, 2} = Hammer.check_rate(bucket, 1000, 2)
  end

  test "returns expected tuples on inspect_bucket" do
    bucket1 = bucket()
    bucket2 = bucket()

    assert {:ok, {0, 2, _, nil, nil}} = Hammer.inspect_bucket(bucket1, 1000, 2)
    assert {:allow, 1} = Hammer.check_rate(bucket1, 1000, 2)
    assert {:ok, {1, 1, _, _, _}} = Hammer.inspect_bucket(bucket1, 1000, 2)
    assert {:allow, 2} = Hammer.check_rate(bucket1, 1000, 2)

    assert {:allow, 1} = Hammer.check_rate(bucket2, 1000, 2)
    assert {:ok, {2, 0, _, _, _}} = Hammer.inspect_bucket(bucket1, 1000, 2)
    assert {:deny, 2} = Hammer.check_rate(bucket1, 1000, 2)
    assert {:ok, {3, 0, ms_to_next_bucket, _, _}} = Hammer.inspect_bucket(bucket1, 1000, 2)

    assert ms_to_next_bucket < 1000
  end

  test "returns expected tuples on delete_buckets" do
    bucket1 = bucket()
    bucket2 = bucket()
    bucket3 = bucket()

    assert {:allow, 1} = Hammer.check_rate(bucket1, 1000, 2)
    assert {:allow, 2} = Hammer.check_rate(bucket1, 1000, 2)
    assert {:deny, 2} = Hammer.check_rate(bucket1, 1000, 2)
    assert {:allow, 1} = Hammer.check_rate(bucket2, 1000, 2)
    assert {:allow, 2} = Hammer.check_rate(bucket2, 1000, 2)
    assert {:deny, 2} = Hammer.check_rate(bucket2, 1000, 2)
    assert {:ok, 1} = Hammer.delete_buckets(bucket1)
    assert {:allow, 1} = Hammer.check_rate(bucket1, 1000, 2)
    assert {:deny, 2} = Hammer.check_rate(bucket2, 1000, 2)

    assert {:ok, 0} = Hammer.delete_buckets(bucket3)
  end

  test "count_hit_inc" do
    bucket = bucket()
    assert {:allow, 4} = Hammer.check_rate_inc(bucket, 1000, 10, 4)
    assert {:allow, 9} = Hammer.check_rate_inc(bucket, 1000, 10, 5)
    assert {:deny, 10} = Hammer.check_rate_inc(bucket, 1000, 10, 3)
  end

  test "mixing count_hit with count_hit_inc" do
    bucket = bucket()
    assert {:allow, 3} = Hammer.check_rate_inc(bucket, 1000, 10, 3)
    assert {:allow, 4} = Hammer.check_rate(bucket, 1000, 10)
    assert {:allow, 5} = Hammer.check_rate(bucket, 1000, 10)
    assert {:allow, 9} = Hammer.check_rate_inc(bucket, 1000, 10, 4)
    assert {:allow, 10} = Hammer.check_rate(bucket, 1000, 10)
    assert {:deny, 10} = Hammer.check_rate_inc(bucket, 1000, 10, 2)
  end
end
