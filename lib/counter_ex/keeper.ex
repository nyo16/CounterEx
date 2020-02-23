defmodule CounterEx.Keeper do
  use GenServer

  @table_name :counters
  @position 1

  alias __MODULE__
  defstruct table_name: nil, sweep?: nil, interval: nil

  ### Public Api

  @spec start_link(any) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec init(keyword) :: {:ok, CounterEx.Keeper.t()}
  def init(opts) do
    sweep? = Keyword.get(opts, :sweep, nil)
    interval = Keyword.get(opts, :interval, nil)
    if sweep?, do: Process.send_after(self(), :clear_keys, interval)

    ref =
      :ets.new(@table_name, [
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, %Keeper{table_name: ref, sweep?: sweep?, interval: interval}}
  end

  @spec stop :: :ok
  def stop() do
    GenServer.stop(__MODULE__)
  end

  def get_keeper() do
    GenServer.call(__MODULE__, :get_state)
  end

  @spec get_all_values :: [tuple]
  def get_all_values() do
    case :ets.tab2list(@table_name) do
      [] -> nil
      values -> values
    end
  end

  @spec set(binary, integer) :: boolean
  def set(key, value \\ 0) do
    :ets.update_element(@table_name, key, [{@position + 1, value}])
  end

  @spec increment(binary(), integer) :: integer
  def increment(key, value \\ 1) do
    :ets.update_counter(@table_name, key, @position, {value, 0})
  end

  def decrement(key, value \\ -1) do
    :ets.update_counter(@table_name, key, @position, {value, 0})
  end

  def reset(key, value \\ 0) do
    set(key, value)
  end

  @spec reset_all :: true
  def reset_all() do
    :ets.delete_all_objects(@table_name)
  end

  @spec get_value(binary) :: [tuple]
  def get_value(key) do
    case :ets.lookup(@table_name, key) do
      [] -> nil
      [{^key, value}] -> value
    end
  end

  #### GenServer handles

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end
end
