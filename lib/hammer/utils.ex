defmodule Hammer.Utils do

  # Returns Erlang Time as milliseconds since 00:00 GMT, January 1, 1970
  def timestamp do
    Datetime.utc_now() |> DateTime.to_unix(:millisecond)
  end

end
