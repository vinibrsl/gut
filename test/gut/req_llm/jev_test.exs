defmodule Gut.ReqLLM.JevTest do
  use ExUnit.Case, async: true

  alias Gut.Error
  alias Gut.ReqLLM.Jev

  describe "init/1" do
    test "requires a model" do
      assert_raise ArgumentError, ~r/requires a :model option/, fn -> Jev.init([]) end
    end
  end

  describe "choose/4" do
    test "selects through ReqLLM evaluation" do
      plug = fn conn ->
        Req.Test.json(conn, %{
          "model" => "jev-latest",
          "answers" => %{"choice" => %{"type" => "choice", "choice" => "1"}},
          "usage" => %{"input_tokens" => 1, "output_tokens" => 1, "total_tokens" => 2}
        })
      end

      assert {:ok, :yes} =
               Gut.feel("subject", "Question?", [:no, :yes], adapter: adapter(plug))
    end

    test "maps authorization failures" do
      for status <- [401, 403], do: assert_http_error(status, :unauthorized)
    end

    test "maps HTTP timeout failures" do
      for status <- [408, 504], do: assert_http_error(status, :timeout)
    end

    test "maps rate limit failures" do
      assert_http_error(429, :rate_limited)
    end

    test "maps other HTTP failures to adapter errors" do
      assert_http_error(500, :adapter_error)
    end

    test "maps transport timeouts" do
      plug = &Req.Test.transport_error(&1, :timeout)

      assert {:error, %Error{reason: :timeout, cause: %ReqLLM.Error.API.Request{}}} =
               Gut.feel("subject", "Question?", [:yes], adapter: adapter(plug))
    end

    test "maps malformed evaluation responses to adapter errors" do
      plug = fn conn -> Req.Test.json(conn, %{"unexpected" => true}) end

      assert {:error, %Error{reason: :adapter_error}} =
               Gut.feel("subject", "Question?", [:yes], adapter: adapter(plug))
    end

    test "maps failures that have no stable category to adapter errors" do
      state = Jev.init(model: "unknown:model")

      assert {:error, %Error{reason: :adapter_error, cause: :unknown_provider}} =
               Jev.choose("subject", "question", [{"0", "yes"}], state)
    end
  end

  defp assert_http_error(status, reason) do
    plug = fn conn ->
      conn
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(%{"error" => "failed"})
    end

    assert {:error, %Error{reason: ^reason, cause: %ReqLLM.Error.API.Request{status: ^status}}} =
             Gut.feel("subject", "Question?", [:yes], adapter: adapter(plug))
  end

  defp adapter(plug) do
    {Jev,
     model: "typesafe:jev-latest", api_key: "test", max_retries: 0, req_http_options: [plug: plug]}
  end
end
