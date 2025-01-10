defmodule RingLogger.ServerTest do
  use ExUnit.Case, async: false

  require Logger

  import ExUnit.CaptureLog

  alias RingLogger.Server

  @file_path "/tmp/file.log"

  @sample_log %{
    level: :debug,
    message: "This is test msg for recovery",
    metadata: [
      index: 0,
      request_id: 1012,
      file: "demo.ex",
      line: 28,
      module: "demo",
      function: "sample",
      time: 1_735_160_108_000_011
    ],
    module: "Blofeld_firmware",
    timestamp: "2024-12-19 08:05:30"
  }

  setup do
    opts = [
      buffers: %{},
      persist_path: @file_path,
      persist_seconds: 1,
      max_size: 1024,
      circular_buffer: 100
    ]

    {:ok, pid} = Server.start_link(opts)

    state = :sys.get_state(pid)

    {:ok, %{state: state, pid: pid}}
  end

  setup do
    on_exit(fn ->
      if File.exists?(@file_path), do: File.rm(@file_path)
    end)
  end

  test "Persist path not configured", %{state: state} do
    state = %{state | persist_path: nil}

    assert capture_log(fn ->
             Server.handle_info(:tick, state)
           end) =~ "RingLogger attempt to persisting log when the path () is invalid"
  end

  test "tick handle with appropriate state", %{state: state} do
    state = %{state | persist_path: @file_path}
    assert {:noreply, _data} = Server.handle_info(:tick, state)
  end

  test "testing tick handle when user inputs garbage string as a integer for persist_seconds", %{
    state: state
  } do
    state = %{state | persist_seconds: "100"}

    assert_raise ArithmeticError, fn ->
      Server.handle_info(:tick, state)
    end
  end

  test "Logs are persisted when persistence_path is available upon termination", %{
    state: state
  } do
    msg = {@sample_log.module, @sample_log.message, @sample_log.timestamp, @sample_log.metadata}

    # insert some logs manually to servers circular buffer
    _ = Server.log(:debug, msg)

    # this triggers terminate callback and saves ringlogger buffer data
    assert :ok = Server.stop()
    assert File.exists?(@file_path)
    # This line checks if we have successfully saved the data and able to read it again?
    assert [@sample_log] = RingLogger.Persistence.load(state.persist_path)
  end

  test "Logs are not persisted when persistence_path not available upon termination", %{
    pid: pid
  } do
    msg = {@sample_log.module, @sample_log.message, @sample_log.timestamp, @sample_log.metadata}

    # insert some logs manually to servers circular buffer
    _ = Server.log(:debug, msg)

    :sys.replace_state(pid, fn state ->
      %{
        state
        | persist_path: nil
      }
    end)

    assert :ok = Server.stop()
    refute File.exists?(@file_path)
  end
end
