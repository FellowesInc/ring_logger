defmodule RingLogger.Server_persist_path do
  @moduledoc """

   Test case setup tests newly implmented Persist on reboot feature
  Refer FAQM 1583 to understand more details.

  """

  use ExUnit.Case, async: false

  require Logger

  alias RingLogger.Server

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

  # this will define a callback to be run before each test in a case.
  setup do
    opts = [
      buffers: %{},
      persist_path: "/tmp/file.log",
      persist_seconds: 2,
      max_size: 1024,
      circular_buffer: 100
    ]

    # remove file if present
    File.rm(opts[:persist_path])

    {:ok, pid} = Server.start_link(opts)

    state = :sys.get_state(pid)

    {:ok, %{state: state}}
  end

  setup(context) do
    RingLogger.ApplicationEnvHelpers.with_application_env(context, &on_exit/1)
    :ok
  end

  @doc """
  test 1 - asserts return value of tick handle to given tuple.
  if asserts hold true test case is passed
  """
  test "tick handle with appropriate state", %{state: state} do
    assert {:noreply, _data} = Server.handle_info(:tick, state)
  end

  @doc """
  test 2 - asserts return value of tick handle to given tuple when persist path not provided.
  if asserts hold true test case is passed.
  Note - NA
  """

  test "testing tick handle when persist path not available", %{state: state} do
    state = %{state | persist_path: 123}

    assert :ok = Server.handle_info(:tick, state)

    assert :ok = Server.stop()
  end

  @doc """

  test 3 - testing tick handle when user inputs garbage string as a integer
  Note -  Failed this test case even if default persisit seconds are mentioned as 300 secs.
  if persist seconfds anything else than interger must be rejected. No such impelementation done as performed for path

  """

  test "testing tick handle when user inputs garbage string as a integer", %{state: state} do
    state = %{state | persist_seconds: "grabage string"}

    assert :ok = Server.handle_info(:tick, state)

    assert :ok = Server.stop()
  end

  @doc """

  test 4 - terminate genserver on garbage values and validate if the logs have been saved!
  description : Forcefully terminated the Genserver and then tried to retrive log files to check if the logs have persisted or not.
  Note - NA

  """

  test "terminate genserver on garbage values and validate if the logs have been saved!", %{
    state: state
  } do
    msg =
      {"Blofeld_firmware", "This is test msg for recovery", "2024-12-19 08:05:30",
       [
         index: 0,
         request_id: 1012,
         file: "demo.ex",
         line: 28,
         module: "demo",
         function: "sample",
         time: 1_735_160_108_000_011
       ]}

    # insert some logs manually to servers circular buffer
    _ = Server.log(:debug, msg)

    # this triggers terminate callback and saves ringlogger buffer data
    assert :ok = Server.stop()

    # This line checks if we have successfully saved the data and able to read it again?
    assert [@sample_log] = RingLogger.Persistence.load(state.persist_path)
  end
end
