defmodule Greeter do
  def hello(name), do: "Hello #{name}"
end

defmodule Bench do
  use ExUnit.Case

  test "bench" do
    # server-side
    function_list = [{Greeter, :hello, 1}]
    start_supervised!({Exrpc.Server, name: :rpc_server, port: 5670, mfa_list: function_list})

    # client-side
    start_supervised!(
      {Exrpc.Client, name: :rpc_client, host: "localhost", port: 5670, pool_size: 5}
    )

    Benchee.run(
      %{
        "hello_world" => fn -> Exrpc.call(:rpc_client, Greeter, :hello, ["world"]) end
      },
      parallel: System.schedulers_online()
    )
  end
end
