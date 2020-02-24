defmodule CounterEx.Keeper do
  @moduledoc """
  A "singleton" counter storage.
  """
  use GenServer

  @table_name :counters
  @position 1

  alias __MODULE__
  defstruct table_name: nil, interval: nil

  @table_opts [
    :public,
    :named_table,
    read_concurrency: true,
    write_concurrency: true
  ]

  ### Public Api

  @spec start_link(any) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec init(keyword) :: {:ok, any}
  def init(opts) do
    interval = Keyword.get(opts, :interval, nil)
    if interval, do: Process.send_after(self(), :sweep, interval)

    @table_name = :ets.new(@table_name, @table_opts)

    {:ok, %Keeper{table_name: @table_name, interval: interval}}
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
    case :ets.update_element(@table_name, key, {@position + 1, value}) do
      true -> value
      false -> :ets.insert(@table_name, {key, value})
    end
  end


  @spec increment(
          any,
          [{integer, integer} | {integer, integer, integer, integer}]
          | integer
          | {integer, integer}
          | {integer, integer, integer, integer},
          any
        ) :: [integer] | integer
  def increment(key, value \\ 1, default \\ 0) do
    :ets.update_counter(@table_name, key, value, {1, default})
  end

  @spec reset(binary, integer) :: boolean
  def reset(key, value \\ 0) do
    set(key, value)
  end

  @spec reset_all :: true
  def reset_all() do
    :ets.delete_all_objects(@table_name)
  end

  @spec get_value(binary) :: nil | integer
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

  def handle_info(:sweep, state) do
    Process.send_after(self(), :sweep, state.interval)
    :ets.delete_all_objects(state.table_name)
    {:noreply, state}
  end
end
