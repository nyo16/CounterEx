defmodule CounterEx do
  @moduledoc """
  Documentation for CounterEx.
  """

  alias CounterEx.Keeper

  @spec start_keeper :: {CounterEx.Keeper, []}
  def start_keeper() do
    {Keeper, []}
  end

  @spec start_keeper_with_sweep(integer) :: {CounterEx.Keeper, [{:interval, integer}, ...]}
  def start_keeper_with_sweep(interval) when is_integer(interval) do
    {Keeper, [interval: interval]}
  end

  def start_keeper_with_sweep(_), do: {:error, :interval_is_not_integer}

  @doc """
  Create/Update the counter by 1 (default) or custom step.
  Returns the new value

  ## Examples

      iex> CounterEx.inc("sample.key")
      1
      iex> CounterEx.inc("sample.key")
      2
      iex> CounterEx.inc(:sample_key)
      1

  """
  @spec inc(binary, integer) :: integer
  def inc(key, step \\ 1, default \\ 0)
      when (is_binary(key) or is_atom(key)) and is_integer(step),
      do: Keeper.increment(key, step, default)

  @doc """
  Returns the value of the counter or nil

  ## Examples

      iex> CounterEx.get("sample.key")
      nil
      iex> CounterEx.inc("sample.key") && CounterEx.get("sample.key")
      1

  """
  @spec get(binary) :: nil | integer
  def get(key) when is_binary(key) or is_atom(key), do: Keeper.get_value(key)

  @doc """
  Returns all the counters as list ex. [{key, value}....{key, value}]

  ## Examples

      iex> CounterEx.all
      nil
      iex> CounterEx.inc("sample.key") && CounterEx.all
      [{"sample.key", 1}]

  """
  @spec all :: [tuple, ...]
  def all(), do: Keeper.get_all_values()

  @doc """
  Reset the value of a counter to 0 or custom step

  ## Examples

      iex> CounterEx.reset("test.key")
      true

  """
  @spec reset(binary) :: boolean
  def reset(key, initial_value \\ 0) when is_binary(key) or is_atom(key),
    do: Keeper.reset(key, initial_value)

  @doc """
  Set the value of a counter to 0 or custom step

  ## Examples

      iex> CounterEx.set("test.key")
      true

  """
  @spec set(binary, integer) :: boolean
  def set(key, value \\ 0), do: Keeper.set(key, value)

  def benchmark(parallel \\ 2) do
    {:ok, _pid} = CounterEx.Keeper.start_link()

    Benchee.run(
      %{
        "simple key inc" => fn -> CounterEx.inc("test.key") end
      },
      parallel: parallel
    )

    CounterEx.Keeper.stop()

    {:ok, _pid} = CounterEx.Keeper.start_link(interval: 1_000)

    Benchee.run(
      %{
        "simple key inc with sweep" => fn -> CounterEx.inc("test.key") end
      },
      parallel: parallel
    )

    CounterEx.Keeper.stop()
  end
end
