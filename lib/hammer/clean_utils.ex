defmodule Hammer.CleanUtils do
  @moduledoc false

  require Logger

  @type before_clean :: (atom(), [map()] -> any()) | {module(), atom(), list()}

  @doc false
  def invoke_before_clean(callback, algorithm, entries) do
    case callback do
      {mod, fun, extra_args} -> apply(mod, fun, [algorithm, entries | extra_args])
      fun when is_function(fun, 2) -> fun.(algorithm, entries)
    end
  rescue
    e ->
      Logger.warning(
        "before_clean callback raised: #{Exception.format(:error, e, __STACKTRACE__)}"
      )
  catch
    kind, reason ->
      Logger.warning("before_clean callback failed: #{inspect({kind, reason})}")
  end

  @doc false
  def delete_expired(table, expired) do
    Enum.each(expired, fn entry -> :ets.delete_object(table, entry) end)
  end
end
