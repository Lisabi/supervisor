defmodule SampleSupervisor do
  @type ret_type() :: {atom(), {pid(), tuple()}}

  use GenServer
  # client functions
  def start_link(child_spec_list) do
    GenServer.start_link(__MODULE__, [child_spec_list])
  end

  def start_child(supervisor, child_spec) do
    GenServer.call(supervisor, {:start_child, child_spec})
  end

  def terminate_child(supervisor, pid) when is_pid(pid) do
    GenServer.call(supervisor, {:terminate_child, pid})
  end

  def restart_child(supervisor, pid, child_spec) when is_pid(pid) do
    GenServer.call(supervisor, {:restart_child, pid, child_spec})
  end

  def count_children(supervisor) do
    GenServer.call(supervisor, :count_children)
  end

  def which_children(supervisor) do
    GenServer.call(supervisor, :which_children)
  end

  # Server functions

  def init([child_spec_list]) do
    Process.flag(:trap_exit, true)

    state =
      child_spec_list
      |> start_children
      |> Enum.into(%{})

    {:ok, state}
  end

  def handle_info({:EXIT, from, :killed}, state) do
    new_state = Map.delete(state, from)
    {:noreply, new_state}
  end

  def handle_info({:EXIT, from, :normal}, state) do
    IO.inspect("Doing normal")
    new_state = Map.delete(state, from)
    {:noreply, new_state}
  end

  def handle_info({:EXIT, old_pid, _reason}, state) do
    case Map.fetch(state, old_pid) do
      {:ok, child_spec} ->
        case restart_child(old_pid, child_spec) do
          {:ok, {new_pid, child_spec}} ->
            new_state =
              Map.delete(state, old_pid)
              |> Map.put(new_pid, child_spec)

            IO.inspect(new_state)

            {:noreply, new_state}

          :error ->
            {:noreply, state}
        end

      _ ->
        {:noreply, state}
    end
  end

  def handle_call(:count_children, _rom, state) do
    {:reply, map_size(state), state}
  end

  def handle_call(:which_children, _rom, state) do
    {:reply, state, state}
  end

  def handle_call({:terminate_child, pid}, _, state) do
    case terminate_child(pid) do
      :ok ->
        new_state = state |> Map.delete(pid)
        {:reply, :ok, new_state}

      :error ->
        {:reply, {:error, "error terminating child"}, state}
    end
  end

  def handle_call({:start_child, child_spec}, _, state) do
    case start_child(child_spec) do
      {:ok, pid} ->
        new_state = state |> Map.put(pid, child_spec)
        {:reply, {:ok, pid}, new_state}

      :error ->
        {:reply, {:error, "error starting child"}, state}
    end
  end

  def handle_call({:restart_child, old_pid, _}, _from, state) do
    case Map.fetch(state, old_pid) do
      {:ok, child_spec} ->
        case restart_child(old_pid, child_spec) do
          {:ok, {pid, child_spec}} ->
            new_state =
              state
              |> Map.delete(old_pid)
              |> Map.put(pid, child_spec)

            {:reply, {:ok, pid}, new_state}

          :error ->
            {:reply, {:error, "error restarting child"}, state}
        end

      _ ->
        {:reply, :ok, state}
    end
  end

  # private functions
  @spec restart_child(pid(), tuple()) :: ret_type() | atom()
  defp restart_child(pid, child_spec) when is_pid(pid) do
    case terminate_child(pid) do
      :ok ->
        case start_child(child_spec) do
          {:ok, new_pid} ->
            {:ok, {new_pid, child_spec}}

          :error ->
            :error
        end

      :error ->
        :error
        # end
    end
  end

  @spec terminate_child(pid()) :: atom()
  def terminate_child(pid) do
    Process.exit(pid, :kill)
    :ok
  end

  @spec start_child(atom()) :: {atom(), pid()} | atom()
  defp start_child({mod, fun, args}) do
    case apply(mod, fun, args) do
      pid when is_pid(pid) ->
        Process.link(pid)
        {:ok, pid}

      _ ->
        :error
    end
  end

  defp start_children([child_spec | rest]) do
    case start_child(child_spec) do
      {:ok, pid} ->
        [{pid, child_spec} | start_children(rest)]

      :error ->
        :error
    end
  end

  defp start_children([]), do: []
end
