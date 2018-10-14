defmodule RingLogger do
  @behaviour :gen_event

  @moduledoc """
  This is an in-memory ring buffer backend for the Elixir Logger.

  Install it by adding it to your `config.exs`:

  ```elixir
  use Mix.Config

  # Add the RingLogger backend. This removes the
  # default :console backend.
  config :logger, backends: [RingLogger]

  # Set the number of messages to hold in the circular buffer
  config :logger, RingLogger, max_size: 1024
  ```

  Or add manually:

  ```elixir
  Logger.add_backend(RingLogger)
  Logger.configure(RingLogger, max_size: 1024)
  ```

  Once added as a backend, you have two options depending on whether you're
  accessing the `RingLogger` via the IEx prompt or via code.  If you're at the
  IEx prompt, use the helper methods in here like `attach`, `detach`, `next`,
  `tail`, `grep`, etc. They'll automate a few things behind the scenes. If
  you're writing a program that needs to get log messages, use `get` or
  `start_link` a `RingLogger.Client` and call its methods directly.
  """

  alias RingLogger.{Server, Autoclient}

  @typedoc "Option values used by the ring logger"
  @type server_option :: {:max_size, pos_integer()}

  @typedoc "Option values used by client-side functions like `attach` and `tail`"
  @type client_option ::
          {:io, term}
          | {:color, term}
          | {:metadata, Logger.metadata()}
          | {:format, String.t() | custom_formatter}
          | {:level, Logger.level()}
          | {:module_levels, map()}

  @typedoc "A tuple holding a raw, unformatted log entry"
  @type entry ::
          {module(), Logger.level(), Logger.message(), Logger.Formatter.time(), Logger.metadata()}

  @typep custom_formatter :: {module, function}

  #
  # API
  #

  @doc """
  Attach the current IEx session to the logger. It will start printing log messages.

  Options include:
  * `:io` - Defaults to `:stdio`
  * `:colors` -
  * `:metadata` - A KV list of additional metadata
  * `:format` - A custom format string
  * `:level` - The minimum log level to report.
  * `:module_levels` - A map of module to log level for module level logging. For example,
    %{MyModule => :error, MyOtherModule => :none}
  """
  @spec attach([client_option]) :: :ok
  defdelegate attach(opts \\ []), to: Autoclient

  @doc """
  Detach the current IEx session from the logger.
  """
  @spec detach() :: :ok
  defdelegate detach(), to: Autoclient

  @doc """
  Print the next messages in the log.
  """
  @spec next([client_option]) :: :ok | {:error, term()}
  defdelegate next(opts \\ []), to: Autoclient

  @doc """
  Print the last n messages in the log.
  """
  @spec tail(non_neg_integer(), [client_option]) :: :ok | {:error, term()}
  def tail(), do: Autoclient.tail(10, [])
  def tail(opts) when is_list(opts), do: Autoclient.tail(10, opts)
  def tail(n) when is_integer(n), do: Autoclient.tail(n, [])
  def tail(n, opts), do: Autoclient.tail(n, opts)

  @doc """
  Reset the index into the log for `tail/1` to the oldest entry.
  """
  @spec reset([client_option]) :: :ok | {:error, term()}
  defdelegate reset(opts \\ []), to: Autoclient

  @doc """
  Run a regular expression on each entry in the log and print out the matchers.

  For example:

  iex> RingLogger.grep(~r/something/)
  :ok
  """
  @spec grep(Regex.t(), [client_option]) :: :ok | {:error, term()}
  defdelegate grep(regex, opts \\ []), to: Autoclient

  @doc """
  Helper method for formatting log messages per the current client's
  configuration.
  """
  @spec format(entry()) :: :ok
  defdelegate format(message), to: Autoclient

  @doc """
  Get n log messages starting at the specified index.

  Set n to 0 to get entries to the end
  """
  @spec get(non_neg_integer(), non_neg_integer()) :: [entry()]
  defdelegate get(index \\ 0, n \\ 0), to: Server

  @doc """
  Update the logger configuration.

  Options include:
  * `:max_size` - the max number of log messages to store at a time
  """
  @spec configure([server_option]) :: :ok
  defdelegate configure(opts), to: Server

  #
  # Logger backend callbacks
  #
  @spec init(module()) :: {:ok, term()} | {:error, term()}
  def init(__MODULE__) do
    init({__MODULE__, []})
  end

  @spec init({module(), list()}) :: {:ok, term()} | {:error, term()}
  def init({__MODULE__, opts}) when is_list(opts) do
    env = Application.get_env(:logger, __MODULE__, [])
    opts = Keyword.merge(env, opts)
    Application.put_env(:logger, __MODULE__, opts)
    Server.start_link(opts)
    {:ok, configure(opts)}
  end

  def handle_call({:configure, opts}, _state) do
    env = Application.get_env(:logger, __MODULE__, [])
    opts = Keyword.merge(env, opts)
    Application.put_env(:logger, __MODULE__, opts)
    {:ok, :ok, configure(opts)}
  end

  def handle_event({level, _group_leader, message}, state) do
    Server.log(level, message)
    {:ok, state}
  end

  def handle_event(:flush, state) do
    # No flushing needed for RingLogger
    {:ok, state}
  end

  def handle_info(_, state) do
    # Ignore everything else since it's hard to justify RingLogger crashing
    # on a bad message.
    {:ok, state}
  end

  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  def terminate(_reason, _state) do
    Server.stop()
    :ok
  end
end
