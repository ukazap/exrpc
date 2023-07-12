defmodule Greeter do
  def hello(name), do: "Hello #{name}"
end

defmodule Bench do
  use ExUnit.Case

  test "benchmark" do
    # server-side
    function_list = [&Greeter.hello/1]
    start_supervised!({Exrpc.Server, name: RPC.Server, port: 5670, mfa_list: function_list})

    # client-side
    start_supervised!({Exrpc.Client, name: RPC.Client, host: "localhost", port: 5670})

    "Hello world" = Exrpc.call(RPC.Client, Greeter, :hello, ["world"], 5000)

    Benchee.run(
      %{
        "hello_world" => fn -> Exrpc.call(RPC.Client, Greeter, :hello, ["world"]) end
      },
      parallel: System.schedulers_online()
    )
  end
end
