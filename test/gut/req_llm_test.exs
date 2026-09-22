defmodule Gut.ReqLLMTest do
  use ExUnit.Case, async: true

  alias Gut.Error

  describe "init/1" do
    test "requires a model" do
      assert_raise ArgumentError, ~r/requires a :model option/, fn -> Gut.ReqLLM.init([]) end
    end
  end

  describe "choose/4" do
    test "selects through ReqLLM and maps the ID to the original value" do
      plug = fn conn ->
        Req.Test.json(conn, %{
          "id" => "response-test",
          "model" => "gpt-4o-mini",
          "status" => "completed",
          "output_text" => Jason.encode!(%{"value" => "1"}),
          "output" => [],
          "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
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

    test "maps failures that have no stable category to adapter errors" do
      state = Gut.ReqLLM.init(model: "unknown:model")

      assert {:error, %Error{reason: :adapter_error, cause: :unknown_provider}} =
               Gut.ReqLLM.choose("subject", "question", [{"0", "yes"}], state)
    end
  end

  defp assert_http_error(status, reason) do
    plug = fn conn ->
      conn
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(%{"error" => %{"message" => "failed"}})
    end

    assert {:error, %Error{reason: ^reason, cause: %ReqLLM.Error.API.Request{status: ^status}}} =
             Gut.feel("subject", "Question?", [:yes], adapter: adapter(plug))
  end

  defp adapter(plug) do
    {Gut.ReqLLM,
     model: "openai:gpt-4o-mini", api_key: "test", max_retries: 0, req_http_options: [plug: plug]}
  end
end
