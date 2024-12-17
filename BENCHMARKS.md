Following are different benchmarks for different algorithms. it also comparing with other libraries to give you an idea of how Hammer performs. Clearly 7.x series is much faster than 6.x series. Prior to 7.x series, Hammer had some performance issues.

## Running benchmarks

Install the dependencies

```shell
mix deps.get
```

Run the benchmarks

```shell
MIX_ENV=bench LIMIT=1 SCALE=5000 RANGE=200000 PARALLEL=600 mix run bench/base.exs
```

## 7.x series

Results are from my local machine

```shell
❯ MIX_ENV=bench LIMIT=1 SCALE=5000 RANGE=200000 PARALLEL=600 mix run bench/base.exs
Compiling 8 files (.ex)
parallel: 600
limit: 1
scale: 5000
range: 200000

Operating System: macOS
CPU Information: Apple M1 Max
Number of Available Cores: 10
Available memory: 32 GB
Elixir 1.17.3
Erlang 27.1.2
JIT enabled: true

Benchmark suite executing with the following configuration:
warmup: 14 s
time: 6 s
memory time: 0 ns
reduction time: 0 ns
parallel: 600
inputs: none specified
Estimated total run time: 3 min 20 s

Benchmarking ex_rated ...
Benchmarking hammer_atomic_fix_window ...
Benchmarking hammer_atomic_leaky_bucket ...
Benchmarking hammer_atomic_token_bucket ...
Benchmarking hammer_fix_window ...
Benchmarking hammer_leaky_bucket ...
Benchmarking hammer_sliding_window ...
Benchmarking hammer_token_bucket ...
Benchmarking plug_attack ...
Benchmarking rate_limiter ...
Calculating statistics...
Formatting results...

Name                                 ips        average  deviation         median         99th %
hammer_atomic_token_bucket       28.60 K       34.97 μs  ±1400.75%        0.63 μs        2.17 μs
hammer_atomic_leaky_bucket       28.16 K       35.51 μs  ±1438.27%        0.63 μs        2.13 μs
hammer_atomic_fix_window         21.56 K       46.37 μs  ±1348.09%        0.88 μs        8.50 μs
plug_attack                      15.94 K       62.75 μs  ±1391.65%        0.71 μs       57.88 μs
hammer_leaky_bucket              15.48 K       64.60 μs  ±1329.87%        0.79 μs       68.33 μs
hammer_token_bucket              14.68 K       68.11 μs  ±1326.20%        0.75 μs       76.42 μs
rate_limiter                     14.17 K       70.58 μs  ±1461.48%        2.08 μs       18.63 μs
hammer_fix_window                12.91 K       77.48 μs  ±1287.59%        0.79 μs       68.29 μs
ex_rated                          6.06 K      164.91 μs  ±1647.42%        2.29 μs      117.79 μs
hammer_sliding_window          0.00255 K   391671.28 μs    ±22.88%   394739.80 μs   627207.29 μs

Comparison:
hammer_atomic_token_bucket       28.60 K
hammer_atomic_leaky_bucket       28.16 K - 1.02x slower +0.54 μs
hammer_atomic_fix_window         21.56 K - 1.33x slower +11.40 μs
plug_attack                      15.94 K - 1.79x slower +27.78 μs
hammer_leaky_bucket              15.48 K - 1.85x slower +29.63 μs
hammer_token_bucket              14.68 K - 1.95x slower +33.14 μs
rate_limiter                     14.17 K - 2.02x slower +35.61 μs
hammer_fix_window                12.91 K - 2.22x slower +42.51 μs
ex_rated                          6.06 K - 4.72x slower +129.94 μs
hammer_sliding_window          0.00255 K - 11200.21x slower +391636.31 μs

Extended statistics:

Name                               minimum        maximum    sample size                     mode
hammer_atomic_token_bucket        0.125 μs    60127.88 μs        41.39 M                  0.50 μs
hammer_atomic_leaky_bucket       0.0830 μs   253198.17 μs        41.47 M                  0.50 μs
hammer_atomic_fix_window          0.166 μs    51585.75 μs        33.51 M                  0.75 μs
plug_attack                       0.125 μs   159736.35 μs        23.60 M                  0.63 μs
hammer_leaky_bucket               0.167 μs   152246.55 μs        22.19 M                  0.63 μs
hammer_token_bucket                0.21 μs    37019.11 μs        21.08 M                  0.63 μs
rate_limiter                       0.33 μs    95669.81 μs        19.97 M                     2 μs
hammer_fix_window                 0.166 μs    80411.22 μs        21.27 M                  0.63 μs
ex_rated                           0.75 μs   161347.46 μs        10.68 M                  2.13 μs
hammer_sliding_window           3376.38 μs   848362.89 μs         9.36 K419281.00 μs, 382658.61 μ
```

## 6.x series

Results are from my local machine

```shell
Generated rate_limit app
prallel: 600
limit: 1
scale: 5000
range: 200000

Operating System: macOS
CPU Information: Apple M1 Max
Number of Available Cores: 10
Available memory: 32 GB
Elixir 1.17.2
Erlang 26.2.5.2
JIT enabled: true

Benchmark suite executing with the following configuration:
warmup: 14 s
time: 6 s
memory time: 0 ns
reduction time: 0 ns
parallel: 600
inputs: none specified
Estimated total run time: 1 min 20 s

Benchmarking ex_rated ...
Benchmarking hammer ...
Benchmarking plug_attack ..
Benchmarking rate_limiter ...
Calculating statistics...
Formatting results...

Name                   ips        average  deviation         median         99th %
plug_attack        15.49 K       64.57 μs  ±1164.32%        0.63 μs       75.75 μs
rate_limiter       14.43 K       69.32 μs  ±1481.80%        2.08 μs        7.63 μs
ex_rated            5.10 K      196.02 μs  ±1723.71%        2.21 μs      103.38 μs
hammer              0.60 K     1673.82 μs    ±20.82%     1587.92 μs     3502.98 μs

Comparison:
plug_attack        15.49 K
rate_limiter       14.43 K - 1.07x slower +4.75 μs
ex_rated            5.10 K - 3.04x slower +131.44 μs
hammer              0.60 K - 25.92x slower +1609.25 μs

Extended statistics:

Name                 minimum        maximum    sample size                     mode
plug_attack         0.125 μs    33191.21 μs        25.27 M                  0.50 μs
rate_limiter         0.38 μs   117571.92 μs        20.21 M                     2 μs
ex_rated             0.71 μs   169859.21 μs         8.82 M                  1.88 μs
hammer            1405.46 μs     9620.92 μs         2.15 M               1559.75 μs
