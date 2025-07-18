defmodule AtomicTermKeysTest do
  use ExUnit.Case

  defmodule TestAtomicRateLimit do
    use Hammer, backend: :atomic
  end

  setup do
    TestAtomicRateLimit.start_link(clean_period: :timer.minutes(10))
    :ok
  end

  test "atom keys work with atomic backend" do
    assert {:allow, 1} = TestAtomicRateLimit.hit(:atom_key, 1000, 5)
    assert {:allow, 2} = TestAtomicRateLimit.hit(:atom_key, 1000, 5)
  end

  test "tuple keys work with atomic backend" do
    assert {:allow, 1} = TestAtomicRateLimit.hit({"user", 456}, 1000, 5)
    assert {:allow, 2} = TestAtomicRateLimit.hit({"user", 456}, 1000, 5)
  end

  test "integer keys work with atomic backend" do
    assert {:allow, 1} = TestAtomicRateLimit.hit(789, 1000, 5)
    assert {:allow, 2} = TestAtomicRateLimit.hit(789, 1000, 5)
  end
end
