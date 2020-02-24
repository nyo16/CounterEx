# CounterEx

**CounterEx is a small lib to help dealing with counters.**


[![Build Status](https://github.com/nyo16/CounterEx/workflows/CI/badge.svg)](https://github.com/nyo16/CounterEx/actions)


## Installation

[available in Hex](https://hex.pm/packages/counter_ex), the package can be installed
by adding `counter_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:counter_ex, "~> 0.1.0"}
  ]
end
```

## Usage

```elixir
 # start the counter keeper without sweep
 {:ok, _pid} = CounterEx.Keeper.start_link()
 # or with global sweep 
 {:ok, _pid} = CounterEx.Keeper.start_link(interval: 1_000)
 
 # atoms as keys
 iex(125)> CounterEx.inc(:sample_key)
 1

 # binaries keys too
 iex(136)> CounterEx.inc("sample.key")  
 1

 # reset counter
 iex(4)> CounterEx.reset("sample.key")
 0

 # get value of the counter
 iex(137)> CounterEx.get("sample.key")
 1

 # dec the value of a counter
 iex(122)> CounterEx.inc("test_key", -10)
 -10
 
 # inc the value with default counter value
 iex(150)> CounterEx.inc("new_sample.key", 10, 30)
 40

 # Get all counters with values
 iex(138)> CounterEx.all
 [
  {"sample.key", 1},
  {"test_key", 90},
  {:sample_key, 2}
 ]

```

### Add CounterEx to your Supervisor tree

```elixir

   def start(_type, _args) do
    children = [
      ...other workers,
      CounterEx.start_keeper() or CounterEx.start_keeper_with_sweep(interval: 10_000) # time in ms
    ]

    .......
    Supervisor.start_link(children, opts)
  end
```

## Benchmarking

```elixir
iex(159)> CounterEx.benchmark
Operating System: Linux
CPU Information: Intel(R) Core(TM) i7-8750H CPU @ 2.20GHz
Number of Available Cores: 12
Available memory: 31.26 GB
Elixir 1.9.4
Erlang 22.1.8

Benchmark suite executing with the following configuration:
warmup: 2 s
time: 5 s
memory time: 0 ns
parallel: 2
inputs: none specified
Estimated total run time: 7 s

Benchmarking simple key inc...

Name                     ips        average  deviation         median         99th %
simple key inc        3.66 M      272.94 ns   ±584.90%         267 ns         381 ns
Operating System: Linux
CPU Information: Intel(R) Core(TM) i7-8750H CPU @ 2.20GHz
Number of Available Cores: 12
Available memory: 31.26 GB
Elixir 1.9.4
Erlang 22.1.8

Benchmark suite executing with the following configuration:
warmup: 2 s
time: 5 s
memory time: 0 ns
parallel: 2
inputs: none specified
Estimated total run time: 7 s

Benchmarking simple key inc with sweep...

Name                                ips        average  deviation         median         99th %
simple key inc with sweep        4.06 M      246.12 ns  ±1545.25%         235 ns         354 ns
:ok
```

TBD
* More testing
* More counter types (:atomics|:counters from erlang OTP, HLL, Bloom etc..)
* Telemetry integration

Documentation can be found at [https://hexdocs.pm/counter_ex](https://hexdocs.pm/counter_ex/CounterEx.html).

