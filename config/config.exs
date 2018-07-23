use Mix.Config

config :hammer,
  backend:
    {Hammer.Backend.ETS,
     [
       expiry_ms: 60_000 * 60 * 2,
       cleanup_interval_ms: 60_000 * 2
     ]}

import_config "#{Mix.env()}.exs"
