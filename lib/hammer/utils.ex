defmodule Hammer.Utils do

  # Returns Erlang Time as milliseconds since 00:00 GMT, January 1, 1970
  def timestamp do
    DateTime.utc_now() |> DateTime.to_unix(:millisecond)
  end

  # Returns tuple of {timestamp, key}, where key is {bucket_number, id}
  def stamp_key(id, scale_ms) do
    stamp         = Hammer.Utils.timestamp()
    bucket_number = trunc(stamp/scale_ms)      # with scale_ms = 1 bucket changes every millisecond
    key           = {bucket_number, id}
    {stamp, key}
  end
end
