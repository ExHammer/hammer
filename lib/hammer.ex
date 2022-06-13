defmodule Hammer do
  @moduledoc """
  Documentation for Hammer module.

  This is the main API for the Hammer rate-limiter. This module assumes a
  backend pool has been started, most likely by the Hammer application.
  """

  alias Hammer.Utils

  @spec check_rate(id :: String.t(), scale_ms :: integer, limit :: integer) ::
          {:allow, count :: integer}
          | {:deny, limit :: integer}
          | {:error, reason :: any}
  @doc """
  Check if the action you wish to perform is within the bounds of the rate-limit.

  Args:
  - `id`: String name of the bucket. Usually the bucket name is comprised of
  some fixed prefix, with some dynamic string appended, such as an IP address or
  user id.
  - `scale_ms`: Integer indicating size of bucket in milliseconds
  - `limit`: Integer maximum count of actions within the bucket

  Returns either `{:allow,  count}`, `{:deny,   limit}` or `{:error,  reason}`

  Example:

      user_id = 42076
      case check_rate("file_upload:\#{user_id}", 60_000, 5) do
        {:allow, _count} ->
          # do the file upload
        {:deny, _limit} ->
          # render an error page or something
      end
  """
  def check_rate(id, scale_ms, limit) do
    check_rate(:single, id, scale_ms, limit)
  end

  @spec check_rate(backend :: atom, id :: String.t(), scale_ms :: integer, limit :: integer) ::
          {:allow, count :: integer}
          | {:deny, limit :: integer}
          | {:error, reason :: any}
  @doc """
  Same as `check_rate/3`, but allows specifying a backend.
  """
  def check_rate(backend, id, scale_ms, limit) do
    {stamp, key} = Utils.stamp_key(id, scale_ms)

    case call_backend(backend, :count_hit, [key, stamp]) do
      {:ok, count} ->
        if count > limit do
          {:deny, limit}
        else
          {:allow, count}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec check_rate_inc(
          id :: String.t(),
          scale_ms :: integer,
          limit :: integer,
          increment :: integer
        ) ::
          {:allow, count :: integer}
          | {:deny, limit :: integer}
          | {:error, reason :: any}
  @doc """
  Same as check_rate/3, but allows the increment number to be specified.
  This is useful for limiting apis which have some idea of 'cost', where the cost
  of each hit can be specified.
  """
  def check_rate_inc(id, scale_ms, limit, increment) do
    check_rate_inc(:single, id, scale_ms, limit, increment)
  end

  @spec check_rate_inc(
          backend :: atom,
          id :: String.t(),
          scale_ms :: integer,
          limit :: integer,
          increment :: integer
        ) ::
          {:allow, count :: integer}
          | {:deny, limit :: integer}
          | {:error, reason :: any}
  @doc """
  Same as check_rate_inc/4, but allows specifying a backend.
  """
  def check_rate_inc(backend, id, scale_ms, limit, increment) do
    {stamp, key} = Utils.stamp_key(id, scale_ms)

    case call_backend(backend, :count_hit, [key, stamp, increment]) do
      {:ok, count} ->
        if count > limit do
          {:deny, limit}
        else
          {:allow, count}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec inspect_bucket(id :: String.t(), scale_ms :: integer, limit :: integer) ::
          {:ok,
           {count :: integer, count_remaining :: integer, ms_to_next_bucket :: integer,
            created_at :: integer | nil, updated_at :: integer | nil}}
          | {:error, reason :: any}
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
  def inspect_bucket(id, scale_ms, limit) do
    inspect_bucket(:single, id, scale_ms, limit)
  end

  @spec inspect_bucket(backend :: atom, id :: String.t(), scale_ms :: integer, limit :: integer) ::
          {:ok,
           {count :: integer, count_remaining :: integer, ms_to_next_bucket :: integer,
            created_at :: integer | nil, updated_at :: integer | nil}}
          | {:error, reason :: any}
  @doc """
  Same as inspect_bucket/3, but allows specifying a backend
  """
  def inspect_bucket(backend, id, scale_ms, limit) do
    {stamp, key} = Utils.stamp_key(id, scale_ms)
    ms_to_next_bucket = elem(key, 0) * scale_ms + scale_ms - stamp

    case call_backend(backend, :get_bucket, [key]) do
      {:ok, nil} ->
        {:ok, {0, limit, ms_to_next_bucket, nil, nil}}

      {:ok, {_, count, created_at, updated_at}} ->
        count_remaining = if limit > count, do: limit - count, else: 0
        {:ok, {count, count_remaining, ms_to_next_bucket, created_at, updated_at}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec delete_buckets(id :: String.t()) ::
          {:ok, count :: integer}
          | {:error, reason :: any}
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
  def delete_buckets(id) do
    delete_buckets(:single, id)
  end

  @spec delete_buckets(backend :: atom, id :: String.t()) ::
          {:ok, count :: integer}
          | {:error, reason :: any}
  @doc """
  Same as delete_buckets/1, but allows specifying a backend
  """
  def delete_buckets(backend, id) do
    call_backend(backend, :delete_buckets, [id])
  end

  @spec make_rate_checker(id_prefix :: String.t(), scale_ms :: integer, limit :: integer) ::
          (id :: String.t() ->
             {:allow, count :: integer}
             | {:deny, limit :: integer}
             | {:error, reason :: any})
  @doc """
  Make a rate-checker function, with the given `id` prefix, scale_ms and limit.

  Arguments:

  - `id_prefix`: String prefix to the `id`
  - `scale_ms`: Integer indicating size of bucket in milliseconds
  - `limit`: Integer maximum count of actions within the bucket

  Returns a function which accepts an `id` suffix, which will be combined with
  the `id_prefix`. Calling this returned function is equivalent to:
  `Hammer.check_rate("\#{id_prefix}\#{id}", scale_ms, limit)`

  Example:

      chat_rate_limiter = make_rate_checker("send_chat_message:", 60_000, 20)
      user_id = 203517
      case chat_rate_limiter.(user_id) do
        {:allow, _count} ->
          # allow chat message
        {:deny, _limit} ->
          # deny
      end
  """
  def make_rate_checker(id_prefix, scale_ms, limit) do
    make_rate_checker(:single, id_prefix, scale_ms, limit)
  end

  @spec make_rate_checker(
          backend :: atom,
          id_prefix :: String.t(),
          scale_ms :: integer,
          limit :: integer
        ) ::
          (id :: String.t() ->
             {:allow, count :: integer}
             | {:deny, limit :: integer}
             | {:error, reason :: any})
  @doc """
  """
  def make_rate_checker(backend, id_prefix, scale_ms, limit) do
    fn id ->
      check_rate(backend, "#{id_prefix}#{id}", scale_ms, limit)
    end
  end

  defp call_backend(which, function, args) do
    pool = Utils.pool_name(which)
    backend = Utils.get_backend_module(which)

    :poolboy.transaction(
      pool,
      fn pid -> apply(backend, function, [pid | args]) end,
      # TODO: make timeout configurable
      60000
    )
  end
end
