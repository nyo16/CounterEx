defmodule CounterEx.Keeper do
  @moduledoc """
  GenServer that manages counter storage using pluggable backends.

  The Keeper provides a singleton interface to counter operations, delegating
  to the configured backend (ETS, Atomics, or Counters).

  ## Configuration

  The backend is selected at startup via options:

      # Use ETS backend (default)
      CounterEx.Keeper.start_link(backend: CounterEx.Backend.ETS)

      # Use Atomics backend with custom capacity
      CounterEx.Keeper.start_link(
        backend: CounterEx.Backend.Atomics,
        backend_opts: [capacity: 10_000]
      )

      # Use Counters backend
      CounterEx.Keeper.start_link(backend: CounterEx.Backend.Counters)

  ## Sweep Functionality

  The Keeper optionally supports periodic sweeping (clearing all counters):

      # Clear all counters every 60 seconds
      CounterEx.Keeper.start_link(interval: 60_000)

  """
  use GenServer

  require Logger

  alias CounterEx.Backend

  defstruct backend_module: nil,
            backend_state: nil,
            interval: nil

  @type t :: %__MODULE__{
          backend_module: module(),
          backend_state: term(),
          interval: pos_integer() | nil
        }

  ## Public API

  @doc """
  Start the Keeper GenServer.

  ## Options

  - `:backend` - Backend module (default: `CounterEx.Backend.ETS`)
  - `:backend_opts` - Options passed to backend init (default: `[]`)
  - `:interval` - Sweep interval in milliseconds (default: `nil` - no sweeping)
  - `:name` - GenServer name (default: `__MODULE__`)

  ## Examples

      # Start with ETS backend
      {:ok, pid} = CounterEx.Keeper.start_link()

      # Start with Atomics backend
      {:ok, pid} = CounterEx.Keeper.start_link(
        backend: CounterEx.Backend.Atomics,
        backend_opts: [capacity: 5000]
      )

      # Start with periodic sweep
      {:ok, pid} = CounterEx.Keeper.start_link(interval: 30_000)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Initialize the Keeper with the selected backend.
  """
  @impl true
  def init(opts) do
    backend_module = Keyword.get(opts, :backend, Backend.ETS)
    backend_opts = Keyword.get(opts, :backend_opts, [])
    interval = Keyword.get(opts, :interval)

    case backend_module.init(backend_opts) do
      {:ok, backend_state} ->
        if interval, do: Process.send_after(self(), :sweep, interval)

        Logger.info("CounterEx.Keeper started with backend: #{inspect(backend_module)}")

        {:ok,
         %__MODULE__{
           backend_module: backend_module,
           backend_state: backend_state,
           interval: interval
         }}

      {:error, reason} ->
        Logger.error("Failed to initialize backend #{backend_module}: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @doc """
  Stop the Keeper GenServer.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(server \\ __MODULE__) do
    GenServer.stop(server)
  end

  @doc """
  Increment a counter in the given namespace.
  """
  @spec increment(GenServer.server(), Backend.namespace(), Backend.key(), integer(), integer()) ::
          {:ok, integer()} | {:error, term()}
  def increment(server \\ __MODULE__, namespace, key, step, default) do
    GenServer.call(server, {:inc, namespace, key, step, default})
  end

  @doc """
  Get the value of a counter in the given namespace.
  """
  @spec get_value(GenServer.server(), Backend.namespace(), Backend.key()) ::
          {:ok, integer() | nil} | {:error, term()}
  def get_value(server \\ __MODULE__, namespace, key) do
    GenServer.call(server, {:get, namespace, key})
  end

  @doc """
  Set a counter to a specific value in the given namespace.
  """
  @spec set(GenServer.server(), Backend.namespace(), Backend.key(), integer()) ::
          {:ok, integer()} | {:error, term()}
  def set(server \\ __MODULE__, namespace, key, value) do
    GenServer.call(server, {:set, namespace, key, value})
  end

  @doc """
  Reset a counter to an initial value in the given namespace.
  """
  @spec reset(GenServer.server(), Backend.namespace(), Backend.key(), integer()) ::
          {:ok, integer()} | {:error, term()}
  def reset(server \\ __MODULE__, namespace, key, initial_value \\ 0) do
    GenServer.call(server, {:reset, namespace, key, initial_value})
  end

  @doc """
  Delete a counter in the given namespace.
  """
  @spec delete(GenServer.server(), Backend.namespace(), Backend.key()) :: :ok | {:error, term()}
  def delete(server \\ __MODULE__, namespace, key) do
    GenServer.call(server, {:delete, namespace, key})
  end

  @doc """
  Get all counters in the given namespace.
  """
  @spec get_all_values(GenServer.server(), Backend.namespace()) ::
          {:ok, %{Backend.key() => integer()}} | {:error, term()}
  def get_all_values(server \\ __MODULE__, namespace) do
    GenServer.call(server, {:get_all, namespace})
  end

  @doc """
  Delete all counters in the given namespace.
  """
  @spec delete_namespace(GenServer.server(), Backend.namespace()) :: :ok | {:error, term()}
  def delete_namespace(server \\ __MODULE__, namespace) do
    GenServer.call(server, {:delete_namespace, namespace})
  end

  @doc """
  Compare-and-swap operation.
  """
  @spec compare_and_swap(
          GenServer.server(),
          Backend.namespace(),
          Backend.key(),
          integer(),
          integer()
        ) ::
          {:ok, integer()} | {:error, :mismatch, integer()} | {:error, term()}
  def compare_and_swap(server \\ __MODULE__, namespace, key, expected, new_value) do
    GenServer.call(server, {:cas, namespace, key, expected, new_value})
  end

  @doc """
  Get backend information.
  """
  @spec info(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def info(server \\ __MODULE__) do
    GenServer.call(server, :info)
  end

  ## GenServer Callbacks

  @impl true
  def handle_call({:inc, namespace, key, step, default}, _from, state) do
    case state.backend_module.inc(state.backend_state, namespace, key, step, default) do
      {:ok, value} ->
        {:reply, {:ok, value}, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get, namespace, key}, _from, state) do
    result = state.backend_module.get(state.backend_state, namespace, key)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:set, namespace, key, value}, _from, state) do
    result = state.backend_module.set(state.backend_state, namespace, key, value)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:reset, namespace, key, initial_value}, _from, state) do
    result = state.backend_module.reset(state.backend_state, namespace, key, initial_value)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:delete, namespace, key}, _from, state) do
    result = state.backend_module.delete(state.backend_state, namespace, key)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_all, namespace}, _from, state) do
    result = state.backend_module.get_all(state.backend_state, namespace)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:delete_namespace, namespace}, _from, state) do
    result = state.backend_module.delete_namespace(state.backend_state, namespace)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:cas, namespace, key, expected, new_value}, _from, state) do
    result =
      state.backend_module.compare_and_swap(
        state.backend_state,
        namespace,
        key,
        expected,
        new_value
      )

    {:reply, result, state}
  end

  @impl true
  def handle_call(:info, _from, state) do
    result = state.backend_module.info(state.backend_state)
    {:reply, result, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    if state.interval do
      Process.send_after(self(), :sweep, state.interval)
    end

    # Delete all namespaces on sweep
    case state.backend_module.info(state.backend_state) do
      {:ok, %{namespaces: namespaces}} ->
        Enum.each(namespaces, fn namespace ->
          state.backend_module.delete_namespace(state.backend_state, namespace)
        end)

        Logger.debug("Swept all namespaces: #{inspect(namespaces)}")

      {:error, reason} ->
        Logger.warning("Failed to sweep: #{inspect(reason)}")
    end

    {:noreply, state}
  end
end
