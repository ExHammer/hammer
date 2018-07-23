defmodule Hammer.Backend do
  @moduledoc """
  The backend Behaviour module
  """

  @type bucket_key :: {bucket :: integer, id :: String.t()}
  @type bucket_info ::
          {key :: bucket_key, count :: integer, created :: integer, updated :: integer}

  @callback count_hit(
              key :: bucket_key,
              now :: integer
            ) ::
              {:ok, count :: integer}
              | {:error, reason :: any}

  @callback count_hit(
              key :: bucket_key,
              now :: integer,
              increment :: integer
            ) ::
              {:ok, count :: integer}
              | {:error, reason :: any}

  @callback get_bucket(key :: bucket_key) ::
              {:ok, info :: bucket_info}
              | {:ok, nil}
              | {:error, reason :: any}

  @callback delete_buckets(id :: String.t()) ::
              {:ok, count_deleted :: integer}
              | {:error, reason :: any}
end
