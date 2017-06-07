defmodule HammerTest do
  use ExUnit.Case

  test "the truth" do
    assert 1 + 1 == 2
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
