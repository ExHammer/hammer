defmodule HammerTest do
  use ExUnit.Case, async: true

  setup _context do
    {:ok, pid} = start_server()
    {:ok, exrated_server: pid}
  end

  test "returns {:ok, 1} tuple on first access" do
    assert {:ok, 1} = Hammer.check_rate("my-bucket", 10_000, 10)
  end

  test "returns {:ok, 4} tuple on in-limit checks" do
    assert {:ok, 1} = Hammer.check_rate("my-bucket", 10_000, 10)
    assert {:ok, 2} = Hammer.check_rate("my-bucket", 10_000, 10)
    assert {:ok, 3} = Hammer.check_rate("my-bucket", 10_000, 10)
    assert {:ok, 4} = Hammer.check_rate("my-bucket", 10_000, 10)
  end

  test "returns expected tuples on mix of in-limit and out-of-limit checks" do
    assert {:ok, 1} = Hammer.check_rate("my-bucket", 10_000, 2)
    assert {:ok, 2} = Hammer.check_rate("my-bucket", 10_000, 2)
    assert {:error, 2} = Hammer.check_rate("my-bucket", 10_000, 2)
    assert {:error, 2} = Hammer.check_rate("my-bucket", 10_000, 2)
  end

  test "returns expected tuples on 1000ms bucket check with a sleep in the middle" do
    assert {:ok, 1} = Hammer.check_rate("my-bucket", 1000, 2)
    assert {:ok, 2} = Hammer.check_rate("my-bucket", 1000, 2)
    assert {:error, 2} = Hammer.check_rate("my-bucket", 1000, 2)
    :timer.sleep 1000
    assert {:ok, 1} = Hammer.check_rate("my-bucket", 1000, 2)
    assert {:ok, 2} = Hammer.check_rate("my-bucket", 1000, 2)
    assert {:error, 2} = Hammer.check_rate("my-bucket", 1000, 2)
  end

  test "returns expected tuples on inspect_bucket" do
    assert {0, 2, _, nil, nil} = Hammer.inspect_bucket("my-bucket1", 1000, 2)
    assert {:ok, 1} = Hammer.check_rate("my-bucket1", 1000, 2)
    assert {1, 1, _, _, _} = Hammer.inspect_bucket("my-bucket1", 1000, 2)
    assert {:ok, 2} = Hammer.check_rate("my-bucket1", 1000, 2)
    assert {:ok, 1} = Hammer.check_rate("my-bucket2", 1000, 2)
    assert {2, 0, _, _, _} = Hammer.inspect_bucket("my-bucket1", 1000, 2)
    assert {:error, 2} = Hammer.check_rate("my-bucket1", 1000, 2)
    assert {3, 0, ms_to_next_bucket, _, _} = Hammer.inspect_bucket("my-bucket1", 1000, 2)
    assert ms_to_next_bucket < 1000
  end

  test "returns expected tuples on delete_bucket" do
    assert {:ok, 1} = Hammer.check_rate("my-bucket1", 1000, 2)
    assert {:ok, 2} = Hammer.check_rate("my-bucket1", 1000, 2)
    assert {:error, 2} = Hammer.check_rate("my-bucket1", 1000, 2)
    assert {:ok, 1} = Hammer.check_rate("my-bucket2", 1000, 2)
    assert {:ok, 2} = Hammer.check_rate("my-bucket2", 1000, 2)
    assert {:error, 2} = Hammer.check_rate("my-bucket2", 1000, 2)
    assert :ok = Hammer.delete_bucket("my-bucket1")
    assert {:ok, 1} = Hammer.check_rate("my-bucket1", 1000, 2)
    assert {:error, 2} = Hammer.check_rate("my-bucket2", 1000, 2)

    assert :error = Hammer.delete_bucket("unknown-bucket")
  end

  defp start_server() do
    {:ok, _hammer_ets_pid} = Hammer.ETS.start_link()
    Hammer.start_link(backend: Hammer.ETS)
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
