defmodule Hammer do
  use GenServer

  @default_cleanup_interval_ms 60 * 1000 * 10
  @default_expiry_ms 60 * 1000 * 60 * 2

  @moduledoc """
  Documentation for Hammer.

  # check_rate

  Check if the action you wish to perform is within the bounds of the rate-limit.

  Args:
  - `id`: String name of the bucket. Usually the bucket name is comprised of some fixed prefix,
  with some dynamic string appended, such as an IP address or user id.
  - `scale`: Integer indicating size of bucket in milliseconds
  - `limit`: Integer maximum count of actions within the bucket

  Returns either `{:allow,  count}`, `{:deny,   limit}` or `{:error,  reason}`

  Example:
      user_id = 42076
      case  Hammer.check_rate("file_upload:\#{user_id}", 60_000, 5) do
        {:allow, _count} ->
          # do the file upload
        {:deny, _limit} ->
          # render an error page or something
      end


  # inspect_bucket

  Inspect bucket to get count, count_remaining, ms_to_next_bucket, created_at, updated_at.
  This function is free of side-effects and should be called with the same arguments you
  would use for `check_rate` if you intended to increment and check the bucket counter.

  Arguments:

  - `id`: String name of the bucket. Usually the bucket name is comprised of some fixed prefix,
  with some dynamic string appended, such as an IP address or user id.
  - `scale`: Integer indicating size of bucket in milliseconds
  - `limit`: Integer maximum count of actions within the bucket

  Example:

      Hammer.inspect_bucket("file_upload:2042", 60_000, 5)
      {1, 2499, 29381612, 1450281014468, 1450281014468}


  # delete_buckets

  Delete all buckets belonging to the provided id, including the current one.
  Effectively resets the rate-limit for the id.

  Arguments:

  - `id`: String name of the bucket

  Returns either `{:ok, count}` where count is the number of buckets deleted,
  or `{:error, reason}`.

  Example:

      user_id = 2406
      {:ok, _count} = Hammer.delete_buckets("file_uploads:\#{user_id}")

  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], unquote: true do

      @hammer_backend Keyword.get(opts, :backend, Hammer.Backend.ETS)

      @doc false
      @spec check_rate(id::String.t, scale::integer, limit::integer)
            :: {:allow, count::integer}
             | {:deny,  limit::integer}
             | {:error, reason::String.t}
      def check_rate(id, scale, limit) do
        {stamp, key} = Hammer.Utils.stamp_key(id, scale)
        case apply(@hammer_backend, :count_hit, [key, stamp]) do
          {:ok, count} ->
            if (count > limit) do
              {:deny, limit}
            else
              {:allow, count}
            end
          {:error, reason} ->
            {:error, reason}
        end
      end

      # TODO: check the error reporting here
      @doc false
      @spec inspect_bucket(id::String.t, scale::integer, limit::integer)
            :: {count::integer,
                count_remaining::integer,
                ms_to_next_bucket::integer,
                created_at :: integer | nil,
                updated_at :: integer | nil}
      def inspect_bucket(id, scale, limit) do
        {stamp, key} = Hammer.Utils.stamp_key(id, scale)
        ms_to_next_bucket = (elem(key, 0) * scale) + scale - stamp
        case apply(@hammer_backend, :get_bucket, [key]) do
          nil ->
            {0, limit, ms_to_next_bucket, nil, nil}
          {_, count, created_at, updated_at} ->
            count_remaining = if limit > count, do: limit - count, else: 0
            {count, count_remaining, ms_to_next_bucket, created_at, updated_at}
        end
      end

      @doc false
      @spec delete_buckets(id::String.t) :: {:ok, count::integer } | {:error, reason::String.t}
      def delete_buckets(id) do
        apply(@hammer_backend, :delete_buckets, [id])
      end

    end
  end

  def default_cleanup_interval_ms() do
    @default_cleanup_interval_ms
  end

  def default_expiry_ms do
    @default_expiry_ms
  end

end
