# CounterEx

**High-performance counter library with pluggable backends and namespace support.**

[![Build Status](https://github.com/nyo16/CounterEx/workflows/CI/badge.svg)](https://github.com/nyo16/CounterEx/actions)
[![Hex.pm](https://img.shields.io/hexpm/v/counter_ex.svg)](https://hex.pm/packages/counter_ex)
[![License](https://img.shields.io/hexpm/l/counter_ex.svg)](https://github.com/nyo16/CounterEx/blob/master/LICENSE.md)

CounterEx provides atomic counter operations with three backend options:
- **ETS** (default): Dynamic counters, unlimited capacity
- **Atomics**: Fixed capacity, ultra-fast operations
- **Counters**: Fixed capacity, write-optimized

## Features

- ✨ **Pluggable Backends**: Choose between ETS, Erlang Atomics, or Counters
- 🏷️ **Namespace Support**: Organize counters into logical groups
- ⚡ **High Performance**: Up to 291K operations/second (4 parallel workers)
- 🔒 **Atomic Operations**: Thread-safe increment, set, compare-and-swap
- 📊 **Observability**: Built-in Telemetry integration
- 🎯 **Simple API**: Clean, intuitive function interface
- 🧪 **Well Tested**: Comprehensive test suite with >90% coverage

## Installation

Add `counter_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:counter_ex, "~> 0.2.0"}
  ]
end
```

## Quick Start

```elixir
# Add to your supervision tree
def start(_type, _args) do
  children = [
    {CounterEx, []}  # Uses ETS backend by default
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end

# Basic operations
{:ok, 1} = CounterEx.inc(:my_counter)
{:ok, 2} = CounterEx.inc(:my_counter)
{:ok, 2} = CounterEx.get(:my_counter)

# Use namespaces to organize counters
{:ok, 1} = CounterEx.inc(:http, :requests)
{:ok, 1} = CounterEx.inc(:http, :errors)
{:ok, 1} = CounterEx.inc(:db, :queries)

# Get all counters in a namespace
{:ok, counters} = CounterEx.all(:http)
# => %{requests: 1, errors: 1}
```

## Backend Selection

### ETS (Default) - Best for Dynamic Counters

```elixir
{CounterEx, backend: CounterEx.Backend.ETS}
```

**Use when:**
- You don't know how many counters you'll need
- Counter names/keys are dynamic
- You want the simplest solution

**Performance:** ~256K inc/s, ~270K get/s (4 workers on M4 Max)

### Atomics - Best for Maximum Performance

```elixir
{CounterEx,
  backend: CounterEx.Backend.Atomics,
  backend_opts: [capacity: 10_000]
}
```

**Use when:**
- You have a known, bounded set of counters
- You need maximum performance
- You can estimate capacity upfront

**Performance:** ~253K inc/s, ~291K get/s (4 workers on M4 Max)

### Counters - Best for Write-Heavy Workloads

```elixir
{CounterEx,
  backend: CounterEx.Backend.Counters,
  backend_opts: [capacity: 5_000]
}
```

**Use when:**
- You have write-heavy workloads
- Many concurrent processes incrementing counters
- Write performance is more critical than read performance

**Performance:** ~248K inc/s, ~269K get/s (4 workers on M4 Max)

See the [Backend Comparison Guide](guides/backends.md) for detailed comparison.

## API Overview

### Basic Operations

```elixir
# Increment
{:ok, 1} = CounterEx.inc(:counter)
{:ok, 11} = CounterEx.inc(:counter, 10)
{:ok, 105} = CounterEx.inc(:counter, 5, 100)  # with default value

# Get
{:ok, 105} = CounterEx.get(:counter)
{:ok, nil} = CounterEx.get(:nonexistent)

# Set
{:ok, 42} = CounterEx.set(:counter, 42)

# Reset
{:ok, 0} = CounterEx.reset(:counter)
{:ok, 10} = CounterEx.reset(:counter, 10)

# Delete
:ok = CounterEx.delete(:counter)
```

### Namespace Operations

```elixir
# Increment in namespace
{:ok, 1} = CounterEx.inc(:metrics, :requests, 1, 0)

# Get from namespace
{:ok, 1} = CounterEx.get(:metrics, :requests)

# Get all counters in namespace
{:ok, %{requests: 1, errors: 0}} = CounterEx.all(:metrics)

# Delete entire namespace
:ok = CounterEx.delete_namespace(:metrics)
```

### Advanced Operations

```elixir
# Compare-and-swap
{:ok, 10} = CounterEx.set(:counter, 10)
{:ok, 20} = CounterEx.compare_and_swap(:counter, 10, 20)  # succeeds
{:error, :mismatch, 20} = CounterEx.compare_and_swap(:counter, 10, 30)  # fails

# Get backend info
{:ok, info} = CounterEx.info()
# %{
#   type: :ets,
#   counters_count: 42,
#   namespaces: [:default, :http, :db],
#   ...
# }
```

## Use Cases

### HTTP Request Tracking

```elixir
defmodule MyApp.Metrics do
  def track_request(status) do
    CounterEx.inc(:http, :total_requests)

    case status do
      s when s in 200..299 -> CounterEx.inc(:http, :success)
      s when s in 400..499 -> CounterEx.inc(:http, :client_errors)
      s when s in 500..599 -> CounterEx.inc(:http, :server_errors)
    end
  end

  def get_metrics do
    CounterEx.all(:http)
  end
end
```

### Rate Limiting

```elixir
defmodule MyApp.RateLimiter do
  @max_requests 100

  def check_rate_limit(user_id) do
    key = :"user_#{user_id}"

    case CounterEx.get(:rate_limits, key) do
      {:ok, count} when count >= @max_requests ->
        {:error, :rate_limit_exceeded}

      {:ok, _count} ->
        {:ok, _} = CounterEx.inc(:rate_limits, key)
        :ok

      {:ok, nil} ->
        {:ok, _} = CounterEx.inc(:rate_limits, key, 1, 0)
        :ok
    end
  end
end
```

## Configuration

### Periodic Sweep

Clear all counters periodically:

```elixir
{CounterEx, interval: 60_000}  # Clear every 60 seconds
```

### Multiple Counter Instances

Run multiple instances with different backends:

```elixir
children = [
  # Fast metrics with Atomics
  {CounterEx, name: :metrics, backend: CounterEx.Backend.Atomics, backend_opts: [capacity: 1000]},

  # Dynamic user counters with ETS
  {CounterEx, name: :users, backend: CounterEx.Backend.ETS}
]
```

## Performance

Benchmarks on Apple M4 Max (16 cores, 64GB RAM) with 4 parallel workers:

| Backend | Operation | Throughput | Notes |
|---------|-----------|------------|-------|
| **Atomics** | get() | **291K ops/s** | Fastest reads |
| **Atomics** | inc() | **253K ops/s** | Best overall |
| **Atomics** | set() | **257K ops/s** | |
| **ETS** | get() | **270K ops/s** | |
| **ETS** | inc() | **256K ops/s** | Most flexible |
| **ETS** | set() | **262K ops/s** | |
| **Counters** | get() | **269K ops/s** | |
| **Counters** | inc() | **248K ops/s** | Write-optimized |
| **Counters** | set() | **256K ops/s** | |

**System Configuration:**
- **CPU**: Apple M4 Max (12 performance + 4 efficiency cores)
- **Memory**: 64 GB
- **OS**: macOS 26.1
- **Elixir**: 1.18.4
- **Erlang/OTP**: 28.0.1 (JIT enabled)

Run your own benchmarks:

```elixir
CounterEx.benchmark(parallel: 4)
```

## Telemetry

CounterEx emits telemetry events for observability:

```elixir
:telemetry.attach(
  "counter-handler",
  [:counter_ex, :backend, :ets, :inc],
  &handle_event/4,
  nil
)

def handle_event([:counter_ex, :backend, :ets, :inc], measurements, metadata, _config) do
  # measurements: %{count: 1}
  # metadata: %{namespace: :http, key: :requests, step: 1}
end
```

Events emitted:
- `[:counter_ex, :backend, :ets, :inc]`
- `[:counter_ex, :backend, :ets, :set]`
- `[:counter_ex, :backend, :ets, :delete]`
- `[:counter_ex, :backend, :ets, :cas]`
- ... (similar for atomics and counters backends)

## Migration from 0.1.x

See the [Migration Guide](guides/migration.md) for upgrading from version 0.1.x.

**Key Changes:**
- Return values now use `{:ok, value}` tuples
- `all/0` now returns a map instead of list
- New namespace support
- Pluggable backend architecture

## Documentation

- [API Documentation](https://hexdocs.pm/counter_ex)
- [Backend Comparison Guide](guides/backends.md)
- [Migration Guide](guides/migration.md)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

Copyright 2025 © nyo16

Licensed under the Apache License, Version 2.0. See [LICENSE.md](LICENSE.md) for details.

