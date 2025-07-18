defmodule TermKeysTest do
  use ExUnit.Case

  defmodule TestRateLimit do
    use Hammer, backend: :ets
  end

  setup do
    TestRateLimit.start_link(clean_period: :timer.minutes(10))
    :ok
  end

  test "string keys work" do
    assert {:allow, 1} = TestRateLimit.hit("string_key", 1000, 5)
    assert {:allow, 2} = TestRateLimit.hit("string_key", 1000, 5)
  end

  test "atom keys work" do
    assert {:allow, 1} = TestRateLimit.hit(:atom_key, 1000, 5)
    assert {:allow, 2} = TestRateLimit.hit(:atom_key, 1000, 5)
  end

  test "tuple keys work" do
    assert {:allow, 1} = TestRateLimit.hit({"user", 123}, 1000, 5)
    assert {:allow, 2} = TestRateLimit.hit({"user", 123}, 1000, 5)
  end

  test "integer keys work" do
    assert {:allow, 1} = TestRateLimit.hit(12_345, 1000, 5)
    assert {:allow, 2} = TestRateLimit.hit(12_345, 1000, 5)
  end

  test "list keys work" do
    assert {:allow, 1} = TestRateLimit.hit([1, 2, 3], 1000, 5)
    assert {:allow, 2} = TestRateLimit.hit([1, 2, 3], 1000, 5)
  end

  test "map keys work" do
    key = %{user_id: 123, action: :login}
    assert {:allow, 1} = TestRateLimit.hit(key, 1000, 5)
    assert {:allow, 2} = TestRateLimit.hit(key, 1000, 5)
  end
end
