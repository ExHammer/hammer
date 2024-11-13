defmodule Hammer.ETSTest do
  use ExUnit.Case, async: true

  defmodule RateLimit do
    use Hammer, backend: Hammer.ETS
  end

  setup do
    start_supervised!(RateLimit)
    :ok
  end

  describe "check_rate" do
    test "returns {:ok, 1} tuple on first access" do
      bucket = "bucket"
      scale = :timer.seconds(10)
      limit = 10

      assert {:allow, 1} = RateLimit.check_rate(bucket, scale, limit)
    end

    test "returns {:ok, 4} tuple on in-limit checks" do
      bucket = "bucket"
      scale = :timer.minutes(10)
      limit = 10

      assert {:allow, 1} = RateLimit.check_rate(bucket, scale, limit)
      assert {:allow, 2} = RateLimit.check_rate(bucket, scale, limit)
      assert {:allow, 3} = RateLimit.check_rate(bucket, scale, limit)
      assert {:allow, 4} = RateLimit.check_rate(bucket, scale, limit)
    end

    test "returns expected tuples on mix of in-limit and out-of-limit checks" do
      bucket = "bucket"
      scale = :timer.minutes(10)
      limit = 2

      assert {:allow, 1} = RateLimit.check_rate(bucket, scale, limit)
      assert {:allow, 2} = RateLimit.check_rate(bucket, scale, limit)
      assert {:deny, 2} = RateLimit.check_rate(bucket, scale, limit)
      assert {:deny, 2} = RateLimit.check_rate(bucket, scale, limit)
    end

    @tag :slow
    test "returns expected tuples on 1000ms bucket check with a sleep in the middle" do
      bucket = "bucket"
      scale = :timer.seconds(1)
      limit = 2

      assert {:allow, 1} = RateLimit.check_rate(bucket, scale, limit)
      assert {:allow, 2} = RateLimit.check_rate(bucket, scale, limit)
      assert {:deny, 2} = RateLimit.check_rate(bucket, scale, limit)

      :timer.sleep(1001)

      assert {:allow, 1} = RateLimit.check_rate(bucket, scale, limit)
      assert {:allow, 2} = RateLimit.check_rate(bucket, scale, limit)
      assert {:deny, 2} = RateLimit.check_rate(bucket, scale, limit)
    end

    test "with custom increment" do
      bucket = "cost-bucket"
      scale = :timer.seconds(1)
      limit = 10

      assert {:allow, 4} = RateLimit.check_rate(bucket, scale, limit, 4)
      assert {:allow, 9} = RateLimit.check_rate(bucket, scale, limit, 5)
      assert {:deny, 10} = RateLimit.check_rate(bucket, scale, limit, 3)
    end

    test "mixing default and custom increment" do
      bucket = "cost-bucket"
      scale = :timer.seconds(1)
      limit = 10

      assert {:allow, 3} = RateLimit.check_rate(bucket, scale, limit, 3)
      assert {:allow, 4} = RateLimit.check_rate(bucket, scale, limit)
      assert {:allow, 5} = RateLimit.check_rate(bucket, scale, limit)
      assert {:allow, 9} = RateLimit.check_rate(bucket, scale, limit, 4)
      assert {:allow, 10} = RateLimit.check_rate(bucket, scale, limit)
      assert {:deny, 10} = RateLimit.check_rate(bucket, scale, limit, 2)
    end
  end
end
