defmodule CounterEx.Backend.ETS do
  @moduledoc """
  ETS-based backend for CounterEx.

  This backend uses Erlang Term Storage (ETS) for counter storage, providing:
  - **Dynamic counters**: Create unlimited counters on-demand
  - **High concurrency**: Optimized for both reads and writes
  - **Flexible keys**: Support for atom and binary keys
  - **Per-namespace tables**: Each namespace gets its own ETS table

  ## Characteristics

  - **Performance**: ~3-4M ops/sec
  - **Memory**: Grows dynamically with number of counters
  - **Limitations**: None on counter count or value range

  ## Configuration

  Options:
  - `:base_table_name` - Base name for ETS tables (default: `:counter_ex_ets`)

  ## Example

      {:ok, state} = CounterEx.Backend.ETS.init(base_table_name: :my_counters)
      {:ok, 1} = CounterEx.Backend.ETS.inc(state, :default, :my_counter, 1, 0)
      {:ok, 1} = CounterEx.Backend.ETS.get(state, :default, :my_counter)
  """

  @behaviour CounterEx.Backend

  require Logger

  @table_opts [
    :public,
    :set,
    read_concurrency: true,
    write_concurrency: true
  ]

  @position 1

  defstruct base_name: nil, registry: nil

  @type t :: %__MODULE__{
          base_name: atom(),
          registry: :ets.tid()
        }

  ## Public API

  @impl true
  def init(opts) do
    base_name = Keyword.get(opts, :base_table_name, :counter_ex_ets)

    # Create a registry table to store namespace->table mappings
    registry = :ets.new(:"#{base_name}_registry", [:set, :public])

    state = %__MODULE__{
      base_name: base_name,
      registry: registry
    }

    # Initialize default namespace
    ensure_namespace(state, :default)
    {:ok, state}
  end

  @impl true
  def inc(state, namespace, key, step, default) do
    state = ensure_namespace(state, namespace)
    table = get_table(state, namespace)

    try do
      value = :ets.update_counter(table, key, step, {key, default})
      emit_telemetry(:inc, %{namespace: namespace, key: key, step: step}, state)
      {:ok, value}
    rescue
      e ->
        Logger.error("ETS inc failed: #{inspect(e)}")
        {:error, e}
    end
  end

  @impl true
  def get(state, namespace, key) do
    case :ets.lookup(state.registry, namespace) do
      [] ->
        {:ok, nil}

      [{^namespace, table}] ->
        case :ets.lookup(table, key) do
          [] -> {:ok, nil}
          [{^key, value}] -> {:ok, value}
        end
    end
  end

  @impl true
  def set(state, namespace, key, value) do
    state = ensure_namespace(state, namespace)
    table = get_table(state, namespace)

    case :ets.update_element(table, key, {@position + 1, value}) do
      true ->
        emit_telemetry(:set, %{namespace: namespace, key: key, value: value}, state)
        {:ok, value}

      false ->
        :ets.insert(table, {key, value})
        emit_telemetry(:set, %{namespace: namespace, key: key, value: value}, state)
        {:ok, value}
    end
  end

  @impl true
  def reset(state, namespace, key, initial_value) do
    set(state, namespace, key, initial_value)
  end

  @impl true
  def delete(state, namespace, key) do
    case :ets.lookup(state.registry, namespace) do
      [] ->
        :ok

      [{^namespace, table}] ->
        :ets.delete(table, key)
        emit_telemetry(:delete, %{namespace: namespace, key: key}, state)
        :ok
    end
  end

  @impl true
  def get_all(state, namespace) do
    case :ets.lookup(state.registry, namespace) do
      [] ->
        {:ok, %{}}

      [{^namespace, table}] ->
        counters =
          table
          |> :ets.tab2list()
          |> Enum.into(%{})

        {:ok, counters}
    end
  end

  @impl true
  def delete_namespace(state, namespace) do
    case :ets.lookup(state.registry, namespace) do
      [] ->
        :ok

      [{^namespace, table}] ->
        :ets.delete_all_objects(table)
        emit_telemetry(:delete_namespace, %{namespace: namespace}, state)
        :ok
    end
  end

  @impl true
  def compare_and_swap(state, namespace, key, expected, new_value) do
    state = ensure_namespace(state, namespace)
    table = get_table(state, namespace)

    case :ets.lookup(table, key) do
      [] ->
        # Counter doesn't exist
        if expected == 0 do
          :ets.insert(table, {key, new_value})
          emit_telemetry(:cas, %{namespace: namespace, key: key, success: true}, state)
          {:ok, new_value}
        else
          {:error, :mismatch, 0}
        end

      [{^key, ^expected}] ->
        # Match! Update it
        :ets.update_element(table, key, {@position + 1, new_value})
        emit_telemetry(:cas, %{namespace: namespace, key: key, success: true}, state)
        {:ok, new_value}

      [{^key, current}] ->
        # Mismatch
        emit_telemetry(:cas, %{namespace: namespace, key: key, success: false}, state)
        {:error, :mismatch, current}
    end
  end

  @impl true
  def info(state) do
    namespaces_and_tables = :ets.tab2list(state.registry)

    counters_by_namespace =
      namespaces_and_tables
      |> Enum.map(fn {namespace, table} ->
        {namespace, :ets.info(table, :size)}
      end)
      |> Enum.into(%{})

    total_counters = counters_by_namespace |> Map.values() |> Enum.sum()

    info = %{
      type: :ets,
      backend: __MODULE__,
      base_name: state.base_name,
      namespaces: Enum.map(namespaces_and_tables, fn {ns, _} -> ns end),
      counters_count: total_counters,
      counters_by_namespace: counters_by_namespace
    }

    {:ok, info}
  end

  ## Private Functions

  defp ensure_namespace(%__MODULE__{} = state, namespace) do
    case :ets.lookup(state.registry, namespace) do
      [{^namespace, _table}] ->
        state

      [] ->
        table_name = table_name_for_namespace(state.base_name, namespace)
        table = :ets.new(table_name, @table_opts)
        :ets.insert(state.registry, {namespace, table})
        state
    end
  end

  defp get_table(state, namespace) do
    case :ets.lookup(state.registry, namespace) do
      [{^namespace, table}] -> table
      [] -> raise "Namespace #{namespace} not found"
    end
  end

  defp table_name_for_namespace(base_name, namespace) do
    :"#{base_name}_#{namespace}"
  end

  defp emit_telemetry(operation, metadata, _state) do
    :telemetry.execute(
      [:counter_ex, :backend, :ets, operation],
      %{count: 1},
      metadata
    )
  end
end
