defmodule Hammer.Backend do
  @moduledoc """
  The backend Behaviour module
  """

  @callback count_hit(key :: {bucket :: integer, id :: String.t()}, now :: integer) ::
              {:ok, count :: integer}
              | {:error, reason :: any}

  @callback get_bucket(key :: {bucket :: integer, id :: String.t()}) ::
              {:ok,
               {key :: {bucket :: integer, id :: String.t()}, count :: integer,
                created :: integer, updated :: integer}}
              | {:ok, nil}
              | {:error, reason :: any}

  @callback delete_buckets(id :: String.t()) ::
              {:ok, count_deleted :: integer}
              | {:error, reason :: any}
end
