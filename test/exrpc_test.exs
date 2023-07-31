defmodule RemoteModule do
  def ping(), do: "pong"
  def hello(name), do: "Hello #{name}"
  def goodbye(name), do: "Goodbye #{name}"
  def add(num1, num2), do: num1 + num2
  def sleep(ms), do: :timer.sleep(ms)
  def map_to_list(map), do: Enum.into(map, [])
  def raise_error(message), do: raise(message)
end

defmodule ExrpcTest do
  use ExUnit.Case

  setup do
    name = Stream.repeatedly(fn -> Enum.random(?a..?z) end) |> Enum.take(10) |> to_string()

    [
      server: :"server_#{name}",
      client: :"client_#{name}"
    ]
  end

  describe "empty function list" do
    test "should not be able to start server", ctx do
      function_list = []

      assert_raise ArgumentError, fn ->
        Exrpc.Server.start_link(name: ctx[:server], port: 5670, mfa_list: function_list)
      end
    end
  end

  describe "server and client started" do
    test "rpc calls should work", ctx do
      # server-side
      start_supervised!(
        {Exrpc.Server,
         name: ctx[:server],
         port: 5670,
         mfa_list: [
           &RemoteModule.ping/0,
           &RemoteModule.hello/1,
           &RemoteModule.goodbye/1,
           &RemoteModule.add/2,
           &RemoteModule.map_to_list/1,
           &RemoteModule.raise_error/1
         ]}
      )

      # client-side
      start_supervised!({Exrpc.Client, name: ctx[:client], host: "localhost", port: 5670})

      assert Stream.repeatedly(fn -> Exrpc.mfa_list(ctx[:client]) end)
             |> Enum.any?(fn list ->
               list == [
                 {RemoteModule, :ping, 0},
                 {RemoteModule, :hello, 1},
                 {RemoteModule, :goodbye, 1},
                 {RemoteModule, :add, 2},
                 {RemoteModule, :map_to_list, 1},
                 {RemoteModule, :raise_error, 1}
               ]
             end)

      assert "pong" = Exrpc.call(ctx[:client], RemoteModule, :ping, [])
      assert "Hello world" = Exrpc.call(ctx[:client], RemoteModule, :hello, ["world"])
      assert "Goodbye my love" = Exrpc.call(ctx[:client], RemoteModule, :goodbye, ["my love"])
      assert 5 = Exrpc.call(ctx[:client], RemoteModule, :add, [2, 3])

      map = %{
        name: "John Doe",
        age: 30,
        height: 1.75,
        favorite_fruits: ~w(apple banana),
        person_info: %{name: "John", age: 25},
        numbers: [1, 2, 3],
        language: {:elixir, "programming language"},
        is_active: true,
        no_value: nil,
        current_date: ~D[2023-07-06],
        current_time: ~T[10:30:00],
        timestamp: ~U[2023-07-06T10:30:00Z]
      }

      result = Exrpc.call(ctx[:client], RemoteModule, :map_to_list, [map])
      assert is_list(result)

      assert %{
               name: "John Doe",
               timestamp: ~U[2023-07-06T10:30:00Z],
               language: {:elixir, "programming language"},
               age: 30,
               height: 1.75,
               favorite_fruits: ~w(apple banana),
               person_info: %{name: "John", age: 25},
               numbers: [1, 2, 3],
               is_active: true,
               no_value: nil,
               current_date: ~D[2023-07-06],
               current_time: ~T[10:30:00]
             } = Enum.into(result, %{})

      assert {:badrpc, :invalid_request} =
               Exrpc.call(ctx[:client], RemoteModule, :howdy, ["world"])

      assert {:badrpc, :invalid_request} = Exrpc.call(ctx[:client], RemoteModule, :hello, [])

      assert {:badrpc, %RuntimeError{message: "ugh"}} =
               Exrpc.call(ctx[:client], RemoteModule, :raise_error, ["ugh"])
    end
  end

  describe "server takes too long to reply" do
    test "call should return :timeout error", ctx do
      # server-side
      start_supervised!(
        {Exrpc.Server, name: ctx[:server], port: 5670, mfa_list: [&RemoteModule.sleep/1]}
      )

      # client-side
      start_supervised!({Exrpc.Client, name: ctx[:client], host: "localhost", port: 5670})

      timeout = 10

      assert {:badrpc, :timeout} = Exrpc.call(ctx[:client], RemoteModule, :sleep, [500], timeout)
    end
  end

  describe "server goes down" do
    test "call should return :timeout error", ctx do
      server_pid =
        start_supervised!(
          {Exrpc.Server, name: ctx[:server], port: 5670, mfa_list: [&RemoteModule.hello/1]}
        )

      start_supervised!({Exrpc.Client, name: ctx[:client], host: "localhost", port: 5670})
      assert "Hello world" = Exrpc.call(ctx[:client], RemoteModule, :hello, ["world"], 1000)
      assert "Hello world" = Exrpc.call(ctx[:client], RemoteModule, :hello, ["world"], 100)
      assert "Hello world" = Exrpc.call(ctx[:client], RemoteModule, :hello, ["world"], 100)
      Process.exit(server_pid, :kill)
      assert {:badrpc, :timeout} = Exrpc.call(ctx[:client], RemoteModule, :hello, ["world"], 100)
    end
  end

  describe "server down/unavailable when the client starts" do
    test "call should return :mfa_lookup_fail or :timeout error", ctx do
      start_supervised!({Exrpc.Client, name: ctx[:client], host: "localhost", port: 5670})
      assert {:badrpc, :timeout} = Exrpc.call(ctx[:client], RemoteModule, :hello, ["world"], 1000)
      assert {:badrpc, :timeout} = Exrpc.call(ctx[:client], RemoteModule, :hello, ["world"], 100)
      assert {:badrpc, :timeout} = Exrpc.call(ctx[:client], RemoteModule, :hello, ["world"], 100)
      assert [] = Exrpc.mfa_list(ctx[:client])

      # start_supervised!({Exrpc.Server, name: ctx[:server], port: 5670, mfa_list: [&RemoteModule.hello/1]})
      {:ok, _} =
        Exrpc.Server.start_link(name: ctx[:server], port: 5670, mfa_list: [&RemoteModule.hello/1])

      assert "Hello world" = Exrpc.call(ctx[:client], RemoteModule, :hello, ["world"], 5000)
      assert [{RemoteModule, :hello, 1}] = Exrpc.mfa_list(ctx[:client])
    end
  end

  describe "server shutdown while client is connected" do
    test "should shutdown within shutdown_ms", ctx do
      {:ok, server_pid} =
        Exrpc.Server.start_link(
          name: ctx[:server],
          port: 5670,
          mfa_list: [&RemoteModule.hello/1],
          shutdown_timeout: 500
        )

      Exrpc.Client.start_link(name: ctx[:client], host: "localhost", port: 5670)

      # wait until client and server are connected
      assert "Hello world" = Exrpc.call(ctx[:client], RemoteModule, :hello, ["world"], 5000)

      # shut down server
      Task.async(fn -> Supervisor.stop(ctx[:server], :normal) end)

      Process.sleep(300)
      assert "Hello world" = Exrpc.call(ctx[:client], RemoteModule, :hello, ["world"], 100)
      assert Process.alive?(server_pid)

      Process.sleep(500)
      assert {:badrpc, :timeout} = Exrpc.call(ctx[:client], RemoteModule, :hello, ["world"], 100)
      refute Process.alive?(server_pid)
    end
  end
end
