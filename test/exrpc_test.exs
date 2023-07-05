defmodule Greeter do
  def hello(name), do: "Hello #{name}"
  def goodbye(name), do: "Goodbye #{name}"
end

defmodule Adder do
  def add(num1, num2), do: num1 + num2
end

defmodule Timer do
  def sleep(ms) do
    :timer.sleep(ms)
  end
end

defmodule ExrpcTest do
  use ExUnit.Case
  doctest Exrpc

  describe "empty function list" do
    test "should not be able to start server" do
      function_list = []

      assert_raise ArgumentError, fn ->
        Exrpc.Server.start_link(name: :rpc_server, port: 5670, mfa_list: function_list)
      end
    end
  end

  describe "server and client started" do
    test "call should work" do
      # server-side
      start_supervised!({Exrpc.Server, name: :rpc_server, port: 5670, mfa_list: [{Greeter, :hello, 1}, &Greeter.goodbye/1, &Adder.add/2]})

      # client-side
      start_supervised!({Exrpc.Client, name: :rpc_client, host: "localhost", port: 5670})

      Enum.any?(1..1000000, fn _ -> !is_nil(Exrpc.mfa_list(:rpc_client)) end)
      assert [{Greeter, :hello, 1}, {Greeter, :goodbye, 1}, {Adder, :add, 2}] = Exrpc.mfa_list(:rpc_client)
      assert "Hello world" = Exrpc.call(:rpc_client, Greeter, :hello, ["world"])
      assert "Goodbye my love" = Exrpc.call(:rpc_client, Greeter, :goodbye, ["my love"])
      assert 5 = Exrpc.call(:rpc_client, Adder, :add, [2, 3])
      assert {:badrpc, :invalid_mfa} = Exrpc.call(:rpc_client, Greeter, :howdy, ["world"])
      assert {:badrpc, :invalid_mfa} = Exrpc.call(:rpc_client, Greeter, :hello, [])
    end
  end

  describe "server takes too long to reply" do
    test "call should return :timeout error" do
      # server-side
      start_supervised!({Exrpc.Server, name: :rpc_server, port: 5670, mfa_list: [&Timer.sleep/1]})

      # client-side
      start_supervised!(
        {Exrpc.Client, name: :rpc_client, host: "localhost", port: 5670, send_timeout: 1}
      )

      Enum.any?(1..1000000, fn _ -> !is_nil(Exrpc.mfa_list(:rpc_client)) end)

      receive_timeout_ms = 100
      assert :ok = Exrpc.call(:rpc_client, Timer, :sleep, [1], receive_timeout_ms)
      assert {:badrpc, :timeout} = Exrpc.call(:rpc_client, Timer, :sleep, [350], receive_timeout_ms)
    end
  end

  describe "server down/unavailable" do
    test "call should return :disconnected error" do
      # server-side
      function_list = [{Greeter, :hello, 1}]
      start_supervised!({Exrpc.Server, name: :rpc_server, port: 5670, mfa_list: function_list})

      # client-side
      start_supervised!(
        {Exrpc.Client, name: :rpc_client, host: "localhost", port: 5670, pool_size: 5}
      )

      # stop server
      stop_supervised!({Exrpc.Server, :rpc_server})

      Enum.each(1..1000, fn _ ->
        assert {:badrpc, :disconnected} = Exrpc.call(:rpc_client, Greeter, :hello, ["world"])
      end)

      start_supervised!({Exrpc.Server, name: :rpc_server, port: 5670, mfa_list: function_list})

      Enum.any?(1..1000000, fn _ -> !is_nil(Exrpc.mfa_list(:rpc_client)) end)

      assert "Hello world" = Exrpc.call(:rpc_client, Greeter, :hello, ["world"])
    end

    test "should be able to start client" do
      # client-side
      start_supervised!(
        {Exrpc.Client, name: :rpc_client, host: "localhost", port: 5670, pool_size: 5}
      )

      # server-side
      function_list = [{Greeter, :hello, 1}]
      start_supervised!({Exrpc.Server, name: :rpc_server, port: 5670, mfa_list: function_list})

      assert {:badrpc, :disconnected} = Exrpc.call(:rpc_client, Greeter, :hello, ["world"])
      Enum.any?(1..1000000, fn _ -> !is_nil(Exrpc.mfa_list(:rpc_client)) end)

      assert "Hello world" = Exrpc.call(:rpc_client, Greeter, :hello, ["world"])
    end
  end
end
