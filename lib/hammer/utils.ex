defmodule Hammer.Utils do

  # Returns Erlang Time as milliseconds since 00:00 GMT, January 1, 1970
  def timestamp()
  case Process.get(:current_otp_release) do
    version when version >= 18 ->
      def timestamp(), do: :erlang.system_time(:milli_seconds)
    _ ->
      def timestamp(), do: timestamp(:erlang.now())
  end

  # OTP > 18
  def timestamp({mega, sec, micro}) do
    1000 * (mega * 1000000 + sec) + round(micro/1000)
  end

end
