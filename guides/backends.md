# Backend Comparison Guide

CounterEx supports three different storage backends, each optimized for different use cases. This guide helps you choose the right backend for your application.

## Quick Comparison

| Feature | ETS | Atomics | Counters |
|---------|-----|---------|----------|
| **Capacity** | Unlimited | Fixed | Fixed |
| **Performance** | ~3-4M ops/s | ~10-20M ops/s | ~8-15M ops/s |
| **Memory** | Dynamic | Pre-allocated | Pre-allocated |
| **Best For** | Dynamic counters | Bounded, high-perf | Write-heavy |
| **Setup Complexity** | Easy | Medium | Medium |
| **Counter Limit** | None | Must specify | Must specify |

## Detailed Comparison

### ETS Backend (Default)

The ETS backend uses Erlang Term Storage for counter management.

**Strengths:**
- ✅ Unlimited counters - create as many as you need
- ✅ Dynamic allocation - no capacity planning required
- ✅ Flexible - works for any use case
- ✅ No configuration needed
- ✅ Easy to use

**Weaknesses:**
- ❌ Slower than Atomics/Counters (but still very fast)
- ❌ Memory grows with counter count
- ❌ Slight GC pressure from table operations

**When to Use:**
- You don't know how many counters you'll need
- Counter names/keys are dynamic
- You want the simplest solution
- Performance of ~3-4M ops/s is sufficient
- You're tracking many different metrics

**Configuration:**
```elixir
# Default - no options needed
{CounterEx, []}

# With custom base table name
{CounterEx,
  backend: CounterEx.Backend.ETS,
  backend_opts: [base_table_name: :my_counters]
}
```

**Example Use Cases:**
- Per-user request counters
- Dynamic metric tracking
- Development/prototyping
- Applications with unbounded counter sets

---

### Atomics Backend

The Atomics backend uses Erlang's `:atomics` module for maximum performance.

**Strengths:**
- ✅ Fastest operations (~10-20M ops/s)
- ✅ Fixed memory footprint
- ✅ No GC pressure
- ✅ Minimal overhead
- ✅ Best for bounded counter sets

**Weaknesses:**
- ❌ Fixed capacity - must specify upfront
- ❌ Returns error when capacity exceeded
- ❌ Requires capacity planning
- ❌ Deleted counter slots can be reused but index space is fixed

**When to Use:**
- You have a known, bounded set of counters
- You need maximum performance
- You can estimate capacity upfront
- Memory predictability is important
- You have read-heavy or mixed workloads

**Configuration:**
```elixir
{CounterEx,
  backend: CounterEx.Backend.Atomics,
  backend_opts: [
    capacity: 10_000,  # Max counters per namespace
    signed: true       # Support negative values (default: true)
  ]
}
```

**Capacity Planning:**
```elixir
# Calculate capacity needed
num_servers = 100
metrics_per_server = 50
total_capacity = num_servers * metrics_per_server  # 5,000

{CounterEx,
  backend: CounterEx.Backend.Atomics,
  backend_opts: [capacity: 5_000]
}
```

**Example Use Cases:**
- Fixed set of application metrics
- Per-endpoint request counters (known endpoints)
- Game stats with bounded player count
- Resource pool monitoring

---

### Counters Backend

The Counters backend uses Erlang's `:counters` module, optimized for write-heavy workloads.

**Strengths:**
- ✅ Write-optimized for concurrent updates
- ✅ Fixed memory footprint
- ✅ No GC pressure
- ✅ Better than Atomics for write-heavy scenarios
- ✅ Minimal contention with many writers

**Weaknesses:**
- ❌ Fixed capacity - must specify upfront
- ❌ Slightly slower than Atomics for reads
- ❌ No native CAS (compare-and-swap is emulated)
- ❌ Returns error when capacity exceeded

**When to Use:**
- You have write-heavy workloads
- Many concurrent processes incrementing counters
- You have a known, bounded set of counters
- Write performance is more critical than read performance
- You can estimate capacity upfront

**Configuration:**
```elixir
{CounterEx,
  backend: CounterEx.Backend.Counters,
  backend_opts: [
    capacity: 5_000,              # Max counters per namespace
    write_concurrency: true       # Optimize for concurrent writes (default: true)
  ]
}
```

**Example Use Cases:**
- High-traffic request counters
- Event counting in distributed systems
- Metrics aggregation with many writers
- Rate limiting counters

---

## Choosing the Right Backend

### Decision Tree

```
Do you know how many counters you'll need?
├─ No → Use ETS
└─ Yes
    └─ Is write performance critical with many concurrent writers?
        ├─ Yes → Use Counters
        └─ No → Use Atomics
```

### Performance Comparison

Based on benchmarks (2 parallel workers):

| Operation | ETS | Atomics | Counters |
|-----------|-----|---------|----------|
| inc() | 3.66M ops/s | ~15M ops/s | ~12M ops/s |
| get() | 8.2M ops/s | ~20M ops/s | ~15M ops/s |
| set() | 2.1M ops/s | ~18M ops/s | ~16M ops/s |

*Note: Actual performance depends on your hardware and workload patterns.*

### Memory Comparison

For 10,000 counters:

- **ETS**: ~1.2 MB (actual data) + overhead
- **Atomics**: ~80 KB pre-allocated (8 bytes × 10,000)
- **Counters**: ~80 KB pre-allocated (8 bytes × 10,000)

### Capacity Handling

**ETS:**
```elixir
# Always succeeds (until system memory exhausted)
{:ok, _} = CounterEx.inc(:counter_1000000)
```

**Atomics/Counters:**
```elixir
# Succeeds if within capacity
{:ok, _} = CounterEx.inc(:counter_1)

# Returns error if capacity exceeded
{:error, :capacity_exceeded} = CounterEx.inc(:counter_beyond_capacity)
```

---

## Common Patterns

### Pattern 1: Start with ETS, Optimize Later

```elixir
# Phase 1: Development - use ETS
config :my_app, counter_backend: CounterEx.Backend.ETS

# Phase 2: Production optimization - switch to Atomics
config :my_app,
  counter_backend: CounterEx.Backend.Atomics,
  counter_capacity: 10_000
```

### Pattern 2: Different Backends for Different Purposes

```elixir
# Fast metrics with known set
{CounterEx.Metrics,
  name: :metrics_counters,
  backend: CounterEx.Backend.Atomics,
  backend_opts: [capacity: 1_000]
}

# Dynamic user counters
{CounterEx.Users,
  name: :user_counters,
  backend: CounterEx.Backend.ETS
}
```

### Pattern 3: Namespace-Based Capacity Planning

```elixir
# Each namespace gets its own atomic array
{CounterEx,
  backend: CounterEx.Backend.Atomics,
  backend_opts: [capacity: 100]
}

# :http namespace: 100 counters
# :db namespace: 100 counters
# :cache namespace: 100 counters
# Total: 300 counters across 3 namespaces
```

---

## Migration Between Backends

Switching backends is easy since counter data isn't persisted:

```elixir
# 1. Stop your application
# 2. Update supervision tree
children = [
  # Before
  # {CounterEx, backend: CounterEx.Backend.ETS}

  # After
  {CounterEx,
    backend: CounterEx.Backend.Atomics,
    backend_opts: [capacity: 10_000]
  }
]

# 3. Restart application
# Note: Counters start at 0
```

---

## Troubleshooting

### "Capacity Exceeded" Errors

**Problem:** Getting `{:error, :capacity_exceeded}` with Atomics or Counters

**Solutions:**
1. Increase capacity in configuration
2. Review counter usage with `CounterEx.info()`
3. Delete unused counters with `CounterEx.delete/1-2`
4. Consider switching to ETS backend

```elixir
# Check current usage
{:ok, info} = CounterEx.info()
IO.inspect(info.utilization)  # => 87.5% (875/1000 used)

# If near capacity, increase it
{CounterEx, backend: CounterEx.Backend.Atomics, backend_opts: [capacity: 2000]}
```

### Performance Not Meeting Expectations

**Checklist:**
1. Are you using the right backend for your workload?
2. Is your capacity appropriate (not too large)?
3. Are you properly utilizing namespaces?
4. Check for contention with `CounterEx.info()`

### Memory Issues with ETS

**Problem:** ETS backend using too much memory

**Solution:** Consider switching to fixed-capacity backend:

```elixir
# Calculate required capacity
{:ok, counters} = CounterEx.all()
required_capacity = map_size(counters) * 1.5  # 50% headroom

# Switch to Atomics
{CounterEx,
  backend: CounterEx.Backend.Atomics,
  backend_opts: [capacity: round(required_capacity)]
}
```

---

## Best Practices

1. **Start Simple**: Begin with ETS, optimize later if needed
2. **Monitor Usage**: Use `CounterEx.info()` to track utilization
3. **Plan Capacity**: For Atomics/Counters, overestimate by 25-50%
4. **Use Namespaces**: Organize counters logically
5. **Benchmark**: Test with your actual workload
6. **Document Choice**: Note why you chose a specific backend

---

## Further Reading

- [Erlang Atomics Documentation](https://www.erlang.org/doc/man/atomics.html)
- [Erlang Counters Documentation](https://www.erlang.org/doc/man/counters.html)
- [ETS Performance Characteristics](https://www.erlang.org/doc/man/ets.html)
- [Migration Guide](migration.md)
