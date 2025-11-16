# Migration Guide

## Upgrading from 0.1.x to 0.2.x

CounterEx 0.2.0 introduces major improvements with pluggable backends and namespace support. While we've maintained backward compatibility where possible, some changes may affect your code.

## Breaking Changes

### 1. Return Value Changes

**Before (0.1.x):**
```elixir
CounterEx.inc("key")  # => 1 (integer)
CounterEx.get("key")  # => 1 or nil
CounterEx.set("key", 10)  # => 10 or true
```

**After (0.2.x):**
```elixir
CounterEx.inc("key")  # => {:ok, 1} (tuple)
CounterEx.get("key")  # => {:ok, 1} or {:ok, nil}
CounterEx.set("key", 10)  # => {:ok, 10}
```

**Migration:** Update all CounterEx function calls to pattern match on `{:ok, value}`:

```elixir
# Before
count = CounterEx.inc("requests")

# After
{:ok, count} = CounterEx.inc("requests")
```

### 2. Supervision Tree Changes

**Before (0.1.x):**
```elixir
children = [
  CounterEx.start_keeper()
]
```

**After (0.2.x - Recommended):**
```elixir
children = [
  {CounterEx, []}  # or with options
  {CounterEx, backend: CounterEx.Backend.Atomics, backend_opts: [capacity: 10_000]}
]
```

**Migration:** Replace `CounterEx.start_keeper()` with `{CounterEx, opts}` in your supervision tree. The old API still works for backward compatibility but is deprecated.

### 3. `all/0` Return Type

**Before (0.1.x):**
```elixir
CounterEx.all()  # => [{"key1", 1}, {"key2", 2}] or nil
```

**After (0.2.x):**
```elixir
CounterEx.all()  # => {:ok, %{key1: 1, key2: 2}}
```

**Migration:** Update code to handle the new return format:

```elixir
# Before
case CounterEx.all() do
  nil -> []
  counters -> Enum.map(counters, fn {k, v} -> ... end)
end

# After
{:ok, counters} = CounterEx.all()
Enum.map(counters, fn {k, v} -> ... end)
```

## New Features

### 1. Pluggable Backends

Choose the backend that best fits your use case:

```elixir
# ETS (default) - unlimited dynamic counters
{CounterEx, backend: CounterEx.Backend.ETS}

# Atomics - fixed capacity, ultra-fast
{CounterEx, backend: CounterEx.Backend.Atomics, backend_opts: [capacity: 10_000]}

# Counters - fixed capacity, write-optimized
{CounterEx, backend: CounterEx.Backend.Counters, backend_opts: [capacity: 5_000]}
```

### 2. Namespace Support

Organize your counters into logical namespaces:

```elixir
# Old way - flat key structure
CounterEx.inc("http_requests")
CounterEx.inc("http_errors")
CounterEx.inc("db_queries")

# New way - namespaced
CounterEx.inc(:http, :requests)
CounterEx.inc(:http, :errors)
CounterEx.inc(:db, :queries)

# Get all counters in a namespace
{:ok, http_counters} = CounterEx.all(:http)
# => %{requests: 100, errors: 5}
```

### 3. New Operations

**Delete Individual Counters:**
```elixir
:ok = CounterEx.delete(:my_counter)
```

**Delete Entire Namespace:**
```elixir
:ok = CounterEx.delete_namespace(:metrics)
```

**Compare-and-Swap (CAS):**
```elixir
{:ok, 20} = CounterEx.compare_and_swap(:counter, 10, 20)
# Only updates if current value is 10
```

**Backend Information:**
```elixir
{:ok, info} = CounterEx.info()
# %{type: :ets, counters_count: 42, ...}
```

## Migration Strategies

### Strategy 1: Minimal Changes (Recommended for Quick Migration)

Keep using the ETS backend (default) and update return value handling:

1. Replace all `CounterEx.function()` calls with pattern matching:
   ```elixir
   # Find and replace pattern:
   # From: value = CounterEx.inc(key)
   # To:   {:ok, value} = CounterEx.inc(key)
   ```

2. Update `all/0` calls:
   ```elixir
   # From: CounterEx.all() |> handle_list()
   # To:   {:ok, counters} = CounterEx.all()
   #       counters |> handle_map()
   ```

3. Update supervision tree (optional but recommended):
   ```elixir
   # From: CounterEx.start_keeper()
   # To:   {CounterEx, []}
   ```

### Strategy 2: Gradual Migration with Namespaces

Introduce namespaces gradually:

1. Start by using the default namespace (no code changes needed)
2. Identify logical groupings of counters
3. Migrate groups one at a time to namespaces:

```elixir
# Phase 1: Keep existing counters in default namespace
CounterEx.inc(:requests)  # Uses :default namespace

# Phase 2: New counters use namespaces
CounterEx.inc(:http, :requests)
CounterEx.inc(:db, :queries)

# Phase 3: Migrate old counters to namespaces
# (This requires coordinating the transition)
```

### Strategy 3: Full Migration with Backend Optimization

For new projects or major refactoring:

1. Choose the appropriate backend:
   - **ETS**: Unknown number of counters, need flexibility
   - **Atomics**: Known bounded set, need max performance
   - **Counters**: Write-heavy workload, many concurrent writers

2. Design namespace structure:
   ```elixir
   # By domain
   :http, :db, :cache, :queue

   # By service
   :api, :worker, :scheduler

   # By resource
   :users, :orders, :products
   ```

3. Update all code to use new API

## Compatibility Layer

If you need to maintain compatibility with both versions, create a wrapper module:

```elixir
defmodule MyApp.Counters do
  @counter_ex_version Mix.Project.config()[:deps]
                     |> Enum.find(fn {name, _} -> name == :counter_ex end)
                     |> elem(1)

  if Version.match?(@counter_ex_version, ">= 0.2.0") do
    def inc(key), do: CounterEx.inc(key) |> elem(1)
    def get(key), do: CounterEx.get(key) |> elem(1)
    def all(), do: CounterEx.all() |> elem(1) |> Map.to_list()
  else
    defdelegate inc(key), to: CounterEx
    defdelegate get(key), to: CounterEx
    defdelegate all(), to: CounterEx
  end
end
```

## Testing Your Migration

1. **Update tests** to use new return values
2. **Run the test suite** to catch any missed changes
3. **Check for compilation warnings** about deprecated functions
4. **Monitor performance** after switching backends (if applicable)

## Getting Help

If you encounter issues during migration:

1. Check the [Backend Comparison Guide](backends.md) to ensure you're using the right backend
2. Review the [API documentation](https://hexdocs.pm/counter_ex)
3. Open an issue on [GitHub](https://github.com/nyo16/CounterEx/issues)

## Rollback Plan

If you need to rollback to 0.1.x:

1. Revert mix.exs dependency: `{:counter_ex, "~> 0.1.0"}`
2. Run `mix deps.get`
3. Revert code changes (use version control)
4. Note: Counter data is not persisted, so no data migration needed
