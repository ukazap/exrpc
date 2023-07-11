defmodule RemoteModule do
  def hello(name), do: "Hello #{name}"
  def goodbye(name), do: "Goodbye #{name}"
  def add(num1, num2), do: num1 + num2
  def sleep(ms), do: :timer.sleep(ms)
  def map_to_list(map), do: Enum.into(map, [])
  def raise_error(message), do: raise(message)
end

defmodule ExrpcTest do
  use ExUnit.Case

  describe "empty function list" do
    test "should not be able to start server" do
      function_list = []

      assert_raise ArgumentError, fn ->
        Exrpc.Server.start_link(name: :exrpc_server, port: 5670, mfa_list: function_list)
      end
    end
  end

  describe "server and client started" do
    test "call should work" do
      # server-side
      start_supervised!(
        {Exrpc.Server,
         name: :exrpc_server,
         port: 5670,
         mfa_list: [
           &RemoteModule.hello/1,
           &RemoteModule.goodbye/1,
           &RemoteModule.add/2,
           &RemoteModule.map_to_list/1,
           &RemoteModule.raise_error/1
         ]}
      )

      # client-side
      start_supervised!(
        {Exrpc.Client, name: :rpc_client, host: "localhost", port: 5670, pool_size: 1}
      )

      assert [
               {RemoteModule, :hello, 1},
               {RemoteModule, :goodbye, 1},
               {RemoteModule, :add, 2},
               {RemoteModule, :map_to_list, 1},
               {RemoteModule, :raise_error, 1}
             ] = Exrpc.mfa_list(:rpc_client)

      assert "Hello world" = Exrpc.call(:rpc_client, RemoteModule, :hello, ["world"])
      assert "Goodbye my love" = Exrpc.call(:rpc_client, RemoteModule, :goodbye, ["my love"])
      assert 5 = Exrpc.call(:rpc_client, RemoteModule, :add, [2, 3])

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

      result = Exrpc.call(:rpc_client, RemoteModule, :map_to_list, [map])
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
               Exrpc.call(:rpc_client, RemoteModule, :howdy, ["world"])

      assert {:badrpc, :invalid_request} = Exrpc.call(:rpc_client, RemoteModule, :hello, [])

      assert {:badrpc, %RuntimeError{message: "ugh"}} = Exrpc.call(:rpc_client, RemoteModule, :raise_error, ["ugh"])
    end
  end

  describe "server takes too long to reply" do
    test "call should return :timeout error" do
      # server-side
      start_supervised!(
        {Exrpc.Server, name: :exrpc_server, port: 5670, mfa_list: [&RemoteModule.sleep/1]}
      )

      # client-side
      start_supervised!(
        {Exrpc.Client, name: :rpc_client, host: "localhost", port: 5670}
      )

      timeout = 10

      assert {:badrpc, :timeout} =
               Exrpc.call(:rpc_client, RemoteModule, :sleep, [500], timeout)
    end
  end

  describe "server down/unavailable" do
    test "call should return :disconnected or :mfa_lookup_fail error" do
      # server-side
      start_supervised!(
        {Exrpc.Server, name: :exrpc_server, port: 5670, mfa_list: [&RemoteModule.hello/1]}
      )

      # client-side
      start_supervised!(
        {Exrpc.Client, name: :rpc_client, host: "localhost", port: 5670, pool_size: 5}
      )

      # stop server
      stop_supervised!({Exrpc.Server, :exrpc_server})

      Enum.each(1..1000, fn _ ->
        {:badrpc, reason} = Exrpc.call(:rpc_client, RemoteModule, :hello, ["world"])
        assert reason in [:disconnected, :mfa_lookup_fail]
      end)
    end

    test "should be able to start client" do
      # client-side
      start_supervised!(
        {Exrpc.Client, name: :rpc_client, host: "localhost", port: 5670, pool_size: 5}
      )

      Enum.each(1..1000, fn _ ->
        assert {:badrpc, :disconnected} = Exrpc.call(:rpc_client, RemoteModule, :hello, ["world"])
      end)

      # server-side
      start_supervised!(
        {Exrpc.Server, name: :exrpc_server, port: 5670, mfa_list: [&RemoteModule.hello/1]}
      )

      eventually_succeed =
        Enum.any?(1..100_000, fn _ ->
          case Exrpc.call(:rpc_client, RemoteModule, :hello, ["world"]) do
            "Hello world" ->
              true

            {:badrpc, reason} ->
              assert reason in [:disconnected, :mfa_lookup_fail]
              false
          end
        end)

      assert eventually_succeed
    end
  end
end
