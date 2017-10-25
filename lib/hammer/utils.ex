defmodule Hammer.Utils do
  @moduledoc false

  # Returns Erlang Time as milliseconds since 00:00 GMT, January 1, 1970
  def timestamp do
    DateTime.utc_now() |> DateTime.to_unix(:millisecond)
  end

  # Returns tuple of {timestamp, key}, where key is {bucket_number, id}
  def stamp_key(id, scale_ms) do
    stamp         = timestamp()
    # with scale_ms = 1 bucket changes every millisecond
    bucket_number = trunc(stamp / scale_ms)
    key           = {bucket_number, id}
    {stamp, key}
  end

  def get_backend_module(which) do
    case Application.get_env(:hammer, :backends)[which] do
      {backend_module, _config} ->
        backend_module
      _ ->
        raise KeyError, "backend #{which} is not configured"
    end
  end
  def get_backend_module do
    case Application.get_env(:hammer, :backend) do
      {backend_module, _config} ->
        backend_module
      _ ->
        Hammer.Backend.ETS
    end
  end
end
