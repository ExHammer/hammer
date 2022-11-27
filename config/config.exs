# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
import Config

config :hammer,
  backend:
    {Hammer.Backend.ETS,
     [
       ets_table_name: :hammer_backend_ets_buckets,
       expiry_ms: 60_000 * 60 * 2,
       cleanup_interval_ms: 60_000 * 2
     ]}
