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

defmodule MapToList do
  def convert(map), do: Enum.into(map, [])
end

defmodule ExrpcTest do
  use ExUnit.Case
  doctest Exrpc

  describe "empty function list" do
    test "should not be able to start server" do
      function_list = []

      assert_raise ArgumentError, fn ->
        Exrpc.Server.start_link(name: RPC.Server, port: 5670, mfa_list: function_list)
      end
    end
  end

  describe "server and client started" do
    test "call should work" do
      # server-side
      start_supervised!(
        {Exrpc.Server,
         name: RPC.Server,
         port: 5670,
         mfa_list: [&Greeter.hello/1, &Greeter.goodbye/1, &Adder.add/2, &MapToList.convert/1]}
      )

      # client-side
      start_supervised!({Exrpc.Client, name: RPC.Client, host: "localhost", port: 5670})

      assert [
               {Greeter, :hello, 1},
               {Greeter, :goodbye, 1},
               {Adder, :add, 2},
               {MapToList, :convert, 1}
             ] = Exrpc.mfa_list(RPC.Client)

      assert "Hello world" = Exrpc.call(RPC.Client, Greeter, :hello, ["world"])
      assert "Goodbye my love" = Exrpc.call(RPC.Client, Greeter, :goodbye, ["my love"])
      assert 5 = Exrpc.call(RPC.Client, Adder, :add, [2, 3])

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

      result = Exrpc.call(RPC.Client, MapToList, :convert, [map])
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

      assert {:badrpc, :invalid_mfa} = Exrpc.call(RPC.Client, Greeter, :howdy, ["world"])
      assert {:badrpc, :invalid_mfa} = Exrpc.call(RPC.Client, Greeter, :hello, [])
    end
  end

  describe "server takes too long to reply" do
    test "call should return :timeout error" do
      # server-side
      function_list = [{Timer, :sleep, 1}]
      start_supervised!({Exrpc.Server, name: RPC.Server, port: 5670, mfa_list: function_list})

      # client-side
      start_supervised!(
        {Exrpc.Client, name: RPC.Client, host: "localhost", port: 5670, send_timeout: 1}
      )

      receive_timeout_ms = 1

      assert {:badrpc, :timeout} =
               Exrpc.call(RPC.Client, Timer, :sleep, [350], receive_timeout_ms)
    end
  end

  describe "server down/unavailable" do
    test "call should return :disconnected error" do
      # server-side
      function_list = [{Greeter, :hello, 1}]
      start_supervised!({Exrpc.Server, name: RPC.Server, port: 5670, mfa_list: function_list})

      # client-side
      start_supervised!(
        {Exrpc.Client, name: RPC.Client, host: "localhost", port: 5670, pool_size: 5}
      )

      # stop server
      stop_supervised!({Exrpc.Server, RPC.Server})

      Enum.each(1..1000, fn _ ->
        assert {:badrpc, reason} = Exrpc.call(RPC.Client, Greeter, :hello, ["world"])
        assert reason in [:disconnected, :invalid_mfa]
      end)

      start_supervised!({Exrpc.Server, name: RPC.Server, port: 5670, mfa_list: function_list})

      Enum.each(1..1000, fn _ ->
        Exrpc.call(RPC.Client, Greeter, :hello, ["world"])
      end)

      assert "Hello world" = Exrpc.call(RPC.Client, Greeter, :hello, ["world"])
    end

    test "should be able to start client" do
      # client-side
      start_supervised!(
        {Exrpc.Client, name: RPC.Client, host: "localhost", port: 5670, pool_size: 5}
      )

      # server-side
      function_list = [{Greeter, :hello, 1}]
      start_supervised!({Exrpc.Server, name: RPC.Server, port: 5670, mfa_list: function_list})

      Enum.each(1..1000, fn _ ->
        Exrpc.call(RPC.Client, Greeter, :hello, ["world"])
      end)

      assert "Hello world" = Exrpc.call(RPC.Client, Greeter, :hello, ["world"])
    end
  end
end
