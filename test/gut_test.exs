defmodule GutTest do
  use ExUnit.Case, async: true

  alias Gut.Error

  defmodule PickAdapter do
    @behaviour Gut.Adapter

    @impl true
    def init(opts), do: Keyword.get(opts, :index, 0)

    @impl true
    def choose(_subject, _question, choices, index) do
      {id, _description} = Enum.at(choices, index)
      {:ok, id}
    end
  end

  defmodule DescriptionAdapter do
    @behaviour Gut.Adapter

    @impl true
    def init(opts), do: Keyword.fetch!(opts, :description)

    @impl true
    def choose(_subject, _question, choices, description) do
      {id, ^description} = Enum.find(choices, &(elem(&1, 1) == description))
      {:ok, id}
    end
  end

  defmodule SubjectAdapter do
    @behaviour Gut.Adapter

    @impl true
    def init(opts), do: Keyword.fetch!(opts, :expected)

    @impl true
    def choose(subject, _question, [{id, _}], subject), do: {:ok, id}
  end

  defmodule DerivedSubject do
    @derive {Gut.Subject, only: [:visible]}
    defstruct [:visible, :hidden]
  end

  defmodule CustomSubject do
    defstruct [:value]

    defimpl Gut.Subject do
      def to_text(subject), do: "value=#{subject.value}"
    end
  end

  defmodule ReturnAdapter do
    @behaviour Gut.Adapter

    @impl true
    def init(opts), do: Keyword.fetch!(opts, :return)

    @impl true
    def choose(_subject, _question, _choices, return), do: return
  end

  defmodule UnexpectedAdapter do
    @behaviour Gut.Adapter

    @impl true
    def init(_opts), do: raise("adapter must not run")

    @impl true
    def choose(_subject, _question, _choices, _state), do: raise("adapter must not run")
  end

  describe "feel/4" do
    test "returns the exact value selected from a list" do
      choices = [:no, true, {:team, 3}, 1.0, 1]

      assert {:ok, {:team, 3}} =
               Gut.feel("ticket", "Which value?", choices, adapter: {PickAdapter, index: 2})

      assert {:ok, 1} =
               Gut.feel("ticket", "Which number?", choices, adapter: {PickAdapter, index: 4})
    end

    test "returns keyword keys and range members" do
      assert {:ok, :technical} =
               Gut.feel(
                 "ticket",
                 "Which team?",
                 [
                   billing: "Payment problem",
                   technical: "Product problem"
                 ],
                 adapter: {DescriptionAdapter, description: "Product problem"}
               )

      assert {:ok, 4} =
               Gut.feel("ticket", "How severe?", 1..5, adapter: {PickAdapter, index: 3})
    end

    test "encodes non-string subjects as JSON" do
      assert {:ok, :yes} =
               Gut.feel(%{answer: true}, "Is the answer true?", [:yes],
                 adapter: {SubjectAdapter, expected: ~s({"answer":true})}
               )
    end

    test "uses derived and custom subject representations" do
      assert {:ok, :yes} =
               Gut.feel(
                 %DerivedSubject{visible: "yes", hidden: "secret"},
                 "Is it visible?",
                 [:yes],
                 adapter: {SubjectAdapter, expected: ~s({"visible":"yes"})}
               )

      assert {:ok, :yes} =
               Gut.feel(%CustomSubject{value: 3}, "Which value?", [:yes],
                 adapter: {SubjectAdapter, expected: "value=3"}
               )
    end

    test "rejects invalid questions before calling the adapter" do
      opts = [adapter: UnexpectedAdapter]

      assert_raise ArgumentError, fn -> Gut.feel("subject", "", [:yes], opts) end
      assert_raise ArgumentError, fn -> Gut.feel("subject", :question, [:yes], opts) end
    end

    test "rejects invalid choices before calling the adapter" do
      opts = [adapter: UnexpectedAdapter]

      assert_raise ArgumentError, fn -> Gut.feel("subject", "Question?", [], opts) end
      assert_raise ArgumentError, fn -> Gut.feel("subject", "Question?", [:yes, :yes], opts) end

      assert_raise ArgumentError, fn ->
        Gut.feel("subject", "Question?", [yes: "Yes", yes: "Again"], opts)
      end

      assert_raise ArgumentError, fn -> Gut.feel("subject", "Question?", [yes: true], opts) end

      assert_raise ArgumentError, fn ->
        Gut.feel("subject", "Question?", Enum.to_list(1..101), opts)
      end

      assert_raise ArgumentError, fn -> Gut.feel("subject", "Question?", 1..101, opts) end
      assert_raise ArgumentError, fn -> Gut.feel("subject", "Question?", %{yes: true}, opts) end
    end

    test "rejects subjects that Jason cannot encode before calling the adapter" do
      assert_raise ArgumentError, fn ->
        Gut.feel(self(), "Question?", [:yes], adapter: UnexpectedAdapter)
      end
    end

    test "rejects malformed options and adapters" do
      assert_raise ArgumentError, fn -> Gut.feel("subject", "Question?", [:yes], :invalid) end

      assert_raise ArgumentError, fn ->
        Gut.feel("subject", "Question?", [:yes], unknown: true)
      end

      assert_raise ArgumentError, fn ->
        Gut.feel("subject", "Question?", [:yes], adapter: PickAdapter, adapter: PickAdapter)
      end

      assert_raise ArgumentError, fn ->
        Gut.feel("subject", "Question?", [:yes], adapter: {PickAdapter, [:invalid]})
      end

      assert_raise ArgumentError, fn ->
        Gut.feel("subject", "Question?", [:yes], adapter: String)
      end

      assert_raise ArgumentError, fn ->
        Gut.feel("subject", "Question?", [:yes], adapter: :not_an_adapter)
      end
    end

    test "reports an unknown choice ID" do
      assert {:error, %Error{reason: :invalid_answer, cause: "missing"}} =
               Gut.feel("subject", "Question?", [:yes],
                 adapter: {ReturnAdapter, return: {:ok, "missing"}}
               )
    end

    test "reports adapter contract violations" do
      for result <- [{:ok, 0}, {:error, :failure}, :invalid] do
        assert {:error, %Error{reason: :adapter_error, cause: ^result}} =
                 Gut.feel("subject", "Question?", [:yes],
                   adapter: {ReturnAdapter, return: result}
                 )
      end
    end

    test "returns adapter errors unchanged" do
      error = %Error{reason: :timeout, message: "timed out", cause: :timeout}

      assert {:error, ^error} =
               Gut.feel("subject", "Question?", [:yes],
                 adapter: {ReturnAdapter, return: {:error, error}}
               )
    end
  end

  describe "feel!/4" do
    test "returns the selected choice" do
      assert Gut.feel!("subject", "Question?", [:yes], adapter: PickAdapter) == :yes
    end

    test "raises adapter errors" do
      error = %Error{reason: :timeout, message: "timed out", cause: :timeout}

      assert_raise Error, "timed out", fn ->
        Gut.feel!("subject", "Question?", [:yes],
          adapter: {ReturnAdapter, return: {:error, error}}
        )
      end
    end
  end
end

defmodule Gut.ConfigurationTest do
  use ExUnit.Case, async: false

  setup do
    previous = Application.fetch_env(:gut, :adapter)

    on_exit(fn ->
      case previous do
        {:ok, adapter} -> Application.put_env(:gut, :adapter, adapter)
        :error -> Application.delete_env(:gut, :adapter)
      end
    end)
  end

  describe "adapter configuration" do
    test "call configuration takes precedence over application configuration" do
      Application.put_env(:gut, :adapter, {GutTest.PickAdapter, index: 1})

      assert {:ok, :application} = Gut.feel("subject", "Question?", [:call, :application])

      assert {:ok, :call} =
               Gut.feel("subject", "Question?", [:call, :application],
                 adapter: GutTest.PickAdapter
               )
    end

    test "the default adapter requires configuration" do
      Application.delete_env(:gut, :adapter)

      assert_raise ArgumentError, ~r/requires a :model option/, fn ->
        Gut.feel("subject", "Question?", [:yes])
      end
    end
  end
end
