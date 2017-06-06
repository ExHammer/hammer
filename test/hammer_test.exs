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

end
