defmodule Hammer do
  @moduledoc """
  Documentation for Hammer module.

  This is the main API for the Hammer rate-limiter. This module assumes the
  backend has been started.

  Example:

      def start(_, _) do
        children = [{Hammer.Backend.ETS, cleanup_interval_ms: :timer.seconds(5)}]
        Supervisor.init(children, [])
      end

  """

  @backend Application.compile_env(:hammer, :backend, Hammer.Backend.ETS)

  @doc """
  Check if the action you wish to perform is within the bounds of the rate-limit.

  Args:
  - `id`: String name of the bucket. Usually the bucket name is comprised of
  some fixed prefix, with some dynamic string appended, such as an IP address or
  user id.
  - `scale_ms`: Integer indicating size of bucket in milliseconds
  - `limit`: Integer maximum count of actions within the bucket

  Returns either `{:allow,  count}`, `{:deny,   limit}`

  Example:

      user_id = 42076
      case check_rate("file_upload:\#{user_id}", 60_000, 5) do
        {:allow, _count} ->
          # do the file upload
        {:deny, _limit} ->
          # render an error page or something
      end
  """
  @spec check_rate(id :: String.t(), scale_ms :: integer, limit :: integer) ::
          {:allow, count :: integer} | {:deny, limit :: integer} | {:error, reason :: any}
  def check_rate(id, scale_ms, limit) do
    check_rate_inc(id, scale_ms, limit, 1)
  end

  @doc """
  Same as check_rate/3, but allows the increment number to be specified.
  This is useful for limiting apis which have some idea of 'cost', where the cost
  of each hit can be specified.
  """
  @spec check_rate_inc(
          id :: String.t(),
          scale_ms :: integer,
          limit :: integer,
          increment :: non_neg_integer
        ) ::
          {:allow, count :: integer} | {:deny, limit :: integer} | {:error, reason :: any}
  def check_rate_inc(id, scale_ms, limit, increment) do
    now = System.system_time(:millisecond)
    now_bucket = div(now, scale_ms)
    key = {id, now_bucket}
    expires_at = (now_bucket + 1) * scale_ms

    with {:ok, count} <- @backend.count_hit(key, increment, expires_at) do
      if count <= limit, do: {:allow, count}, else: {:deny, limit}
    end
  end

  @doc """
  Inspect bucket to get count, count_remaining, ms_to_next_bucket, created_at,
  updated_at. This function is free of side-effects and should be called with
  the same arguments you would use for `check_rate` if you intended to increment
  and check the bucket counter.

  Arguments:

  - `id`: String name of the bucket. Usually the bucket name is comprised of
    some fixed prefix,with some dynamic string appended, such as an IP address
    or user id.
  - `scale_ms`: Integer indicating size of bucket in milliseconds
  - `limit`: Integer maximum count of actions within the bucket

  Returns either
  `{:ok, {count, count_remaining, ms_to_next_bucket, created_at, updated_at}`,
  or `{:error, reason}`.

  Example:

      inspect_bucket("file_upload:2042", 60_000, 5)
      {:ok, {1, 2499, 29381612, 1450281014468, 1450281014468}}

  """
  @spec inspect_bucket(id :: String.t(), scale_ms :: integer, limit :: integer) ::
          {:ok,
           {count :: integer, count_remaining :: integer, ms_to_next_bucket :: integer,
            created_at :: integer | nil, updated_at :: integer | nil}}
          | {:error, reason :: any}
  def inspect_bucket(id, scale_ms, limit) do
    now = System.system_time(:millisecond)
    now_bucket = div(now, scale_ms)
    key = {id, now_bucket}
    ms_to_next_bucket = now_bucket * scale_ms + scale_ms - now

    with {:ok, count} <- @backend.get_bucket(key) do
      {:ok,
       {
         count,
         max(limit - count, 0),
         ms_to_next_bucket,
         _created_at = nil,
         _updated_at = nil
       }}
    end
  end

  @doc """
  Delete all buckets belonging to the provided id, including the current one.
  Effectively resets the rate-limit for the id.

  Arguments:

  - `id`: String name of the bucket

  Returns either `{:ok, count}` where count is the number of buckets deleted,
  or `{:error, reason}`.

  Example:

      user_id = 2406
      {:ok, _count} = delete_buckets("file_uploads:\#{user_id}")

  """
  @spec delete_buckets(id :: String.t()) :: {:ok, count :: integer} | {:error, reason :: any}
  def delete_buckets(id) do
    @backend.delete_buckets(id)
  end
end
