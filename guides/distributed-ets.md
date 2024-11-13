# Distributed Rate Limiter with ETS Backend

The example implements a distributed, eventually consistent rate limiter using Phoenix.PubSub for broadcasting each hit across nodes and a local ETS backend to manage rate-limiting counters. This setup is useful when you need to limit the number of actions (e.g., requests) across multiple nodes in a cluster.

Based on [HexpmWeb.RateLimitPubSub.](https://github.com/hexpm/hexpm/blob/main/lib/hexpm_web/rate_limit_pub_sub.ex)

```elixir
defmodule MyApp.RateLimit do
  @moduledoc "Distributed, eventually consistent rate limiter using Phoenix.PubSub and Hammer"
  
  defmodule Local do
    @moduledoc false
    use Hammer, backend: :ets
  end

  use GenServer

  def start_link(opts) do
    children = [
      _local_hammer = {Local, opts},
      _pubsub_listener = %{id: __MODULE__, start: {GenServer, :start_link, [__MODULE__, []]}, type: :worker}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  @pubsub MyApp.PubSub
  @topic "__ratelimit"

  def hit(key, scale, increment \\ 1) do
    :ok = broadcast({:hit, key, scale, increment})
    Local.hit(key, scale, increment)
  end

  def check_rate(key, scale, limit, increment \\ 1) do
    count = hit(key, scale, increment)
    if count <= limit, do: {:allow, count}, else: {:deny, limit}
  end

  defp broadcast(message) do
    {:ok, {Phoenix.PubSub.PG2, adapter_name}} = Registry.meta(@pubsub, :pubsub)
    adapter_name.broadcast(adapter_name, @topic, message)
  end

  @impl true
  def init(_opts) do
    :ok = Phoenix.PubSub.subscribe(@pubsub, @topic)
    {:ok, []}
  end

  @impl true
  def handle_info({:hit, key, scale, increment}, state) do
    _count = Local.hit(key, scale, increment)
    {:noreply, state}
  end
end
```
