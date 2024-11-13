# Distributed Rate Limiter with ETS Backend

The example implements a distributed, eventually consistent rate limiter using Phoenix.PubSub for broadcasting each hit across nodes and a local ETS backend to manage rate-limiting counters. This setup is useful when you need to limit the number of actions (e.g., requests) across multiple nodes in a cluster without introducing extra dependencies.

```elixir
defmodule MyApp.RateLimit do
  @moduledoc "Distributed, eventually consistent rate limiter using Phoenix.PubSub and Hammer"
  
  defmodule Local do
    @moduledoc false
    use Hammer, backend: :ets
  end

  use GenServer

  def start_link(opts) do
    children = [{Local, opts}, MyApp.RateLimit]
    Supervisor.start_link(children, strategy: :one_for_one)
  end

  @pubsub MyApp.PubSub
  @topic __MODULE__

  def hit(key, scale, increment \\ 1) do
    Phoenix.PubSub.broadcast!(@pubsub, @topic, {:hit, key, scale, increment})
    Local.hit(key, scale, increment)
  end

  def check_rate(key, scale, limit, increment \\ 1) do
    count = hit(key, scale, increment)
    if count <= limit, do: {:allow, count}, else: {:deny, limit}
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
