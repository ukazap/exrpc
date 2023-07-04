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

defmodule ExRPCTest do
  use ExUnit.Case
  doctest ExRPC

  describe "empty function list/routes" do
    test "should not be able to start server" do
      function_list = []

      assert_raise ArgumentError, fn ->
        ExRPC.Server.start_link(name: RPC.Server, port: 5670, routes: function_list)
      end
    end
  end

  describe "server and client started" do
    test "call should work" do
      # server-side
      function_list = [{Greeter, :hello, 1}, {Greeter, :goodbye, 1}, {Adder, :add, 2}]
      start_supervised!({ExRPC.Server, name: RPC.Server, port: 5670, routes: function_list})

      # client-side
      start_supervised!({ExRPC.Client, name: RPC.Client, host: "localhost", port: 5670})
      assert ^function_list = ExRPC.routes(RPC.Client)
      assert "Hello world" = ExRPC.call(RPC.Client, Greeter, :hello, ["world"])
      assert "Goodbye my love" = ExRPC.call(RPC.Client, Greeter, :goodbye, ["my love"])
      assert 5 = ExRPC.call(RPC.Client, Adder, :add, [2, 3])
      assert {:badrpc, :invalid_mfa} = ExRPC.call(RPC.Client, Greeter, :howdy, ["world"])
      assert {:badrpc, :invalid_mfa} = ExRPC.call(RPC.Client, Greeter, :hello, [])
    end
  end

  describe "server takes too long to reply" do
    test "call should return :timeout error" do
      # server-side
      function_list = [{Timer, :sleep, 1}]
      start_supervised!({ExRPC.Server, name: RPC.Server, port: 5670, routes: function_list})

      # client-side
      start_supervised!(
        {ExRPC.Client, name: RPC.Client, host: "localhost", port: 5670, send_timeout: 1}
      )

      receive_timeout_ms = 1

      assert {:badrpc, :timeout} =
               ExRPC.call(RPC.Client, Timer, :sleep, [350], receive_timeout_ms)
    end
  end

  describe "server down/unavailable" do
    test "call should return :disconnected error" do
      # server-side
      function_list = [{Greeter, :hello, 1}]
      start_supervised!({ExRPC.Server, name: RPC.Server, port: 5670, routes: function_list})

      # client-side
      start_supervised!(
        {ExRPC.Client, name: RPC.Client, host: "localhost", port: 5670, pool_size: 5}
      )

      # stop server
      stop_supervised!({ExRPC.Server, RPC.Server})

      Enum.each(1..1000, fn _ ->
        assert {:badrpc, :disconnected} = ExRPC.call(RPC.Client, Greeter, :hello, ["world"])
      end)

      start_supervised!({ExRPC.Server, name: RPC.Server, port: 5670, routes: function_list})

      Enum.each(1..1000, fn _ ->
        ExRPC.call(RPC.Client, Greeter, :hello, ["world"])
      end)

      assert "Hello world" = ExRPC.call(RPC.Client, Greeter, :hello, ["world"])
    end

    test "should be able to start client" do
      # client-side
      start_supervised!(
        {ExRPC.Client, name: RPC.Client, host: "localhost", port: 5670, pool_size: 5}
      )

      # server-side
      function_list = [{Greeter, :hello, 1}]
      start_supervised!({ExRPC.Server, name: RPC.Server, port: 5670, routes: function_list})

      Enum.each(1..1000, fn _ ->
        ExRPC.call(RPC.Client, Greeter, :hello, ["world"])
      end)

      assert "Hello world" = ExRPC.call(RPC.Client, Greeter, :hello, ["world"])
    end
  end

  # describe "bench" do
  #   test "bench" do
  #     # server-side
  #     function_list = [{Greeter, :hello, 1}]
  #     start_supervised!({ExRPC.Server, name: RPC.Server, port: 5670, routes: function_list})

  #     # client-side
  #     start_supervised!(
  #       {ExRPC.Client, name: RPC.Client, host: "localhost", port: 5670, pool_size: 5}
  #     )

  #     Benchee.run(
  #       %{
  #         "hello_world" => fn -> ExRPC.call(RPC.Client, Greeter, :hello, ["world"], 1000) end
  #       },
  #       parallel: System.schedulers_online()
  #     )
  #   end
  # end
end
