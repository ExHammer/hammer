defmodule Hammer.Backend do
  @moduledoc """
  The backend Behaviour module.
  """

  @type bucket_key :: {id :: String.t(), bucket :: integer}

  @callback count_hit(bucket_key, increment :: integer, expires_at :: integer) ::
              {:ok, count :: integer} | {:error, reason :: any}

  @callback get_bucket(bucket_key) ::
              {:ok, count :: integer} | {:error, reason :: any}

  @callback delete_buckets(id :: String.t()) ::
              {:ok, count_deleted :: integer} | {:error, reason :: any}
end
