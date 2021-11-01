defmodule HammerBackendRedisTest do
  use ExUnit.Case
  import Mock

  setup _context do
    with_mock Redix, start_link: fn _c -> {:ok, 1} end do
      {:ok, pid} = Hammer.Backend.Redis.start_link(expiry_ms: 60_000)
      {:ok, [pid: pid]}
    end
  end

  test "count_hit, first", context do
    pid = context[:pid]

    with_mock Redix,
      command: fn
        _r, ["WATCH", _] -> {:ok, "OK"}
        _r, ["EXISTS", _] -> {:ok, 0}
      end,
      pipeline: fn _r, _c ->
        {:ok, ["OK", "QUEUED", "QUEUED", "QUEUED", "QUEUED", ["OK", 1, 1, 1]]}
      end do
      assert {:ok, 1} == Hammer.Backend.Redis.count_hit(pid, {1, "one"}, 123)
      assert called(Redix.command(:_, ["EXISTS", "Hammer:Redis:one:1"]))

      assert called(
               Redix.pipeline(:_, [
                 ["MULTI"],
                 [
                   "HMSET",
                   "Hammer:Redis:one:1",
                   "bucket",
                   1,
                   "id",
                   "one",
                   "count",
                   1,
                   "created",
                   123,
                   "updated",
                   123
                 ],
                 [
                   "SADD",
                   "Hammer:Redis:Buckets:one",
                   "Hammer:Redis:one:1"
                 ],
                 [
                   "EXPIRE",
                   "Hammer:Redis:one:1",
                   61
                 ],
                 [
                   "EXPIRE",
                   "Hammer:Redis:Buckets:one",
                   61
                 ],
                 ["EXEC"]
               ])
             )
    end
  end

  test "count_hit, first, with custom increment", context do
    pid = context[:pid]

    with_mock Redix,
      command: fn
        _r, ["WATCH", _] -> {:ok, "OK"}
        _r, ["EXISTS", _] -> {:ok, 0}
      end,
      pipeline: fn _r, _c ->
        {:ok, ["OK", "QUEUED", "QUEUED", "QUEUED", "QUEUED", ["OK", 1, 1, 1]]}
      end do
      assert {:ok, 21} == Hammer.Backend.Redis.count_hit(pid, {1, "one"}, 123, 21)
      assert called(Redix.command(:_, ["EXISTS", "Hammer:Redis:one:1"]))

      assert called(
               Redix.pipeline(:_, [
                 ["MULTI"],
                 [
                   "HMSET",
                   "Hammer:Redis:one:1",
                   "bucket",
                   1,
                   "id",
                   "one",
                   "count",
                   # Increment
                   21,
                   "created",
                   123,
                   "updated",
                   123
                 ],
                 [
                   "SADD",
                   "Hammer:Redis:Buckets:one",
                   "Hammer:Redis:one:1"
                 ],
                 [
                   "EXPIRE",
                   "Hammer:Redis:one:1",
                   61
                 ],
                 [
                   "EXPIRE",
                   "Hammer:Redis:Buckets:one",
                   61
                 ],
                 ["EXEC"]
               ])
             )
    end
  end

  test "count_hit, after", context do
    pid = context[:pid]

    with_mock Redix,
      command: fn _r, _c -> {:ok, 1} end,
      pipeline: fn _r, _c -> {:ok, ["OK", "QUEUED", "QUEUED", [42, 0]]} end do
      assert {:ok, 42} == Hammer.Backend.Redis.count_hit(pid, {1, "one"}, 123)
      assert called(Redix.command(:_, ["EXISTS", "Hammer:Redis:one:1"]))

      assert called(
               Redix.pipeline(:_, [
                 ["MULTI"],
                 ["HINCRBY", "Hammer:Redis:one:1", "count", 1],
                 ["HSET", "Hammer:Redis:one:1", "updated", 123],
                 ["EXEC"]
               ])
             )
    end
  end

  test "count_hit, after, with custom increment", context do
    pid = context[:pid]

    with_mock Redix,
      command: fn _r, _c -> {:ok, 1} end,
      pipeline: fn _r, _c -> {:ok, ["OK", "QUEUED", "QUEUED", [42, 0]]} end do
      assert {:ok, 42} == Hammer.Backend.Redis.count_hit(pid, {1, "one"}, 123, 21)
      assert called(Redix.command(:_, ["EXISTS", "Hammer:Redis:one:1"]))

      assert called(
               Redix.pipeline(:_, [
                 ["MULTI"],
                 # Increment
                 ["HINCRBY", "Hammer:Redis:one:1", "count", 21],
                 ["HSET", "Hammer:Redis:one:1", "updated", 123],
                 ["EXEC"]
               ])
             )
    end
  end

  test "count_hit, handles race condition", context do
    pid = context[:pid]
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    with_mock Redix,
      command: fn
        _r, ["WATCH", _] -> {:ok, "OK"}
        _r, ["EXISTS", _] -> {:ok, Agent.get_and_update(agent, fn c -> {c, 1} end)}
      end,
      pipeline: fn
        _r, args when length(args) == 6 ->
          {:ok, ["OK", "QUEUED", "QUEUED", "QUEUED", "QUEUED", nil]}

        _r, args when length(args) == 4 ->
          {:ok, ["OK", "QUEUED", "QUEUED", [1, 0]]}
      end do
      assert {:ok, 1} == Hammer.Backend.Redis.count_hit(pid, {1, "one"}, 123)
      assert called(Redix.command(:_, ["EXISTS", "Hammer:Redis:one:1"]))

      # First attempt.
      assert called(Redix.command(:_, ["WATCH", "Hammer:Redis:Buckets:one"]))

      assert called(
               Redix.pipeline(:_, [
                 ["MULTI"],
                 [
                   "HMSET",
                   "Hammer:Redis:one:1",
                   "bucket",
                   1,
                   "id",
                   "one",
                   "count",
                   1,
                   "created",
                   123,
                   "updated",
                   123
                 ],
                 [
                   "SADD",
                   "Hammer:Redis:Buckets:one",
                   "Hammer:Redis:one:1"
                 ],
                 [
                   "EXPIRE",
                   "Hammer:Redis:one:1",
                   61
                 ],
                 [
                   "EXPIRE",
                   "Hammer:Redis:Buckets:one",
                   61
                 ],
                 ["EXEC"]
               ])
             )

      # Second attempt.
      assert called(
               Redix.pipeline(:_, [
                 ["MULTI"],
                 ["HINCRBY", "Hammer:Redis:one:1", "count", 1],
                 ["HSET", "Hammer:Redis:one:1", "updated", 123],
                 ["EXEC"]
               ])
             )
    end

    :ok = Agent.stop(agent)
  end

  test "get_bucket", context do
    pid = context[:pid]

    with_mock Redix, command: fn _r, _c -> {:ok, [1, "one", "2", "3", "4"]} end do
      assert {:ok, {{1, "one"}, 2, 3, 4}} == Hammer.Backend.Redis.get_bucket(pid, {1, "one"})

      assert called(
               Redix.command(:_, [
                 "HMGET",
                 "Hammer:Redis:one:1",
                 "bucket",
                 "id",
                 "count",
                 "created",
                 "updated"
               ])
             )
    end

    with_mock Redix, command: fn _r, _c -> {:ok, [nil, nil, nil, nil, nil]} end do
      assert {:ok, nil} == Hammer.Backend.Redis.get_bucket(pid, {1, "one"})

      assert called(
               Redix.command(:_, [
                 "HMGET",
                 "Hammer:Redis:one:1",
                 "bucket",
                 "id",
                 "count",
                 "created",
                 "updated"
               ])
             )
    end
  end

  test "delete buckets", context do
    pid = context[:pid]

    with_mock Redix,
      command: fn _r, _c -> {:ok, ["a", "b"]} end,
      pipeline: fn _r, _c -> {:ok, ["OK", "QUEUED", "QUEUED", [2, 2]]} end do
      assert {:ok, 2} = Hammer.Backend.Redis.delete_buckets(pid, "one")
      assert called(Redix.command(:_, ["SMEMBERS", "Hammer:Redis:Buckets:one"]))

      assert called(
               Redix.pipeline(:_, [
                 ["MULTI"],
                 ["DEL", "a", "b"],
                 ["DEL", "Hammer:Redis:Buckets:one"],
                 ["EXEC"]
               ])
             )
    end
  end
end
