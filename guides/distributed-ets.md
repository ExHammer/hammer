# Distributed Rate Limiter with ETS Backend

The example implements a distributed, eventually consistent rate limiter using Phoenix.PubSub for broadcasting each hit across nodes and a local ETS backend to manage rate-limiting counters. This setup is useful when you need to limit the number of actions (e.g., requests) across multiple nodes in a cluster.

Based on [HexpmWeb.RateLimitPubSub.](https://github.com/hexpm/hexpm/blob/main/lib/hexpm_web/rate_limit_pub_sub.ex)

```elixir
defmodule MyApp.RateLimit do
  @moduledoc """
  Distributed, eventually consistent rate limiter using `Phoenix.PubSub` and `Hammer`.
  
  This module provides a rate-limiting mechanism for requests using a distributed,
  eventually consistent approach. It combines local in-memory counting with a 
  broadcasting mechanism to keep counters in sync across nodes in a cluster.
  """

  def check_rate(key, scale, limit, increment \\ 1) do
    count = hit(key, scale, increment)
    if count <= limit, do: {:allow, count}, else: {:deny, limit}
  end

  # Records a hit locally and broadcasts it to other nodes to synchronize.
  def hit(key, scale, increment \\ 1) do
    :ok = broadcast({:hit, key, scale, increment})
    Local.hit(key, scale, increment)
  end

  defmodule Local do
    @moduledoc false
    use Hammer, backend: :ets
    # This inner module handles local hit counting via Hammer with ETS as a backend.
  end

  defmodule Listener do
    @moduledoc false
    use GenServer

    # Starts the listener process, subscribing to the specified PubSub topic.
    # This process will listen for `:hit` messages to keep local counters in sync.

    @doc false
    def start_link(opts) do
      pubsub = Keyword.fetch!(opts, :pubsub)
      topic = Keyword.fetch!(opts, :topic)
      GenServer.start_link(__MODULE__, {pubsub, topic})
    end

    @impl true
    def init({pubsub, topic}) do
      :ok = Phoenix.PubSub.subscribe(pubsub, topic)
      {:ok, []}
    end    

    # Handles remote `:hit` messages by updating the local counter.

    @impl true
    def handle_info({:hit, key, scale, increment}, state) do      
      _count = Local.hit(key, scale, increment)
      {:noreply, state}
    end
  end

  @pubsub MyApp.PubSub
  @topic "__ratelimit"

  # Sends a message to other nodes in the cluster to synchronize rate-limiting information.
  defp broadcast(message) do
    {:ok, {Phoenix.PubSub.PG2, adapter_name}} = Registry.meta(@pubsub, :pubsub)
    adapter_name.broadcast(adapter_name, @topic, message)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  # Wraps the local Hammer counter and the listener processes under a signle supervisor.
  def start_link(opts) do
    children = [{Local, opts}, {Listener, pubsub: @pubsub, topic: @topic}]
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```
