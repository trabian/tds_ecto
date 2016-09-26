defmodule Tds.Ecto do

  @moduledoc """
  Adapter module for MSSQL.

  It uses `tds` for communicating to the database
  and manages a connection pool with `poolboy`.

  ## Features

    * Full query support (including joins, preloads and associations)
    * Support for transactions
    * Support for data migrations
    * Support for ecto.create and ecto.drop operations
    * Support for transactional tests via `Ecto.Adapters.SQL`

  ## Options

  Mssql options split in different categories described
  below. All options should be given via the repository
  configuration.

  ### Compile time options
  Those options should be set in the config file and require
  recompilation in order to make an effect.
    * `:adapter` - The adapter name, in this case, `Tds.Ecto`
    * `:timeout` - The default timeout to use on queries, defaults to `5000`

  ### Repo options
    * `:filter_null_on_unique_indexes` - Allows unique indexes to filter out null and only match on NOT NULL values

  ### Connection options

    * `:hostname` - Server hostname
    * `:port` - Server port (default: 1433)
    * `:username` - Username
    * `:password` - User password
    * `:parameters` - Keyword list of connection parameters
    * `:ssl` - Set to true if ssl should be used (default: false)
    * `:ssl_opts` - A list of ssl options, see Erlang's `ssl` docs

  ### Pool options

    * `:size` - The number of connections to keep in the pool
    * `:max_overflow` - The maximum overflow of connections (see poolboy docs)
    * `:lazy` - If false all connections will be started immediately on Repo startup (default: true)

  ### Storage options

    * `:encoding` - the database encoding (default: "UTF8")
    * `:template` - the template to create the database from
    * `:lc_collate` - the collation order
    * `:lc_ctype` - the character classification

  """
  require Tds
  use Ecto.Adapters.SQL, :tds
  @behaviour Ecto.Adapter.Storage

  ## Custom MSSQL types

  def load({:embed, _} = type, binary) when is_binary(binary),
    do: super(type, json_library.decode!(binary))
  def load(:map, binary) when is_binary(binary),
    do: super(:map, json_library.decode!(binary))
  def load(:boolean, 0), do: {:ok, false}
  def load(:boolean, 1), do: {:ok, true}
  def load(type, value), do: super(type, value)

  defp json_library, do: Application.get_env(:ecto, :json_library)

  def storage_up(opts) do
    database = Keyword.fetch!(opts, :database)

    extra = ""

    if lc_collate = Keyword.get(opts, :lc_collate) do
      extra = extra <> " COLLATE='#{lc_collate}'"
    end

    {output, status} =
      run_with_sql_conn opts, "CREATE DATABASE " <> database <> extra
    #IO.inspect status
    cond do
      status == 0                                -> :ok
      String.contains?(output[:msg_text], "already exists") -> {:error, :already_up}
      true                                       -> {:error, output}
    end
  end

  @doc false
  def storage_down(opts) do
    {output, status} = run_with_sql_conn(opts, "DROP DATABASE #{opts[:database]}")
    IO.inspect output
    cond do
      status == 0                                -> :ok
      output != nil -> if String.contains?(output[:msg_text], "does not exist"), do: {:error, :already_down}
      true                                       -> {:error, output}
    end
  end

  def execute_ddl(repo, definition, opts) do
    sql = @conn.execute_ddl(definition, repo)
    IO.puts(sql)
    Ecto.Adapters.SQL.query(repo, sql, [], opts)
    :ok
  end

  defp run_with_sql_conn(opts, sql_command) do
    host = opts[:hostname] || System.get_env("MSSQLHOST") || "localhost"
    database = opts[:database] || "master"
    opts = opts
      |> Keyword.put(:database, database)
      |> Keyword.put(:hostname, host)
    case Tds.Ecto.Connection.connect(opts) do
      {:ok, pid} ->
        # Execute the query
        case Tds.Ecto.Connection.query(pid, sql_command, [], []) do
          {:ok, %{}} -> {:ok, 0}
          {_, %Tds.Error{message: _message, mssql: error}} ->
            {error, 1}
        end
      {_,error} ->
        {error, 1}
    end
  end

  def supports_ddl_transaction? do
    true
  end
end
