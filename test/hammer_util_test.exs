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
