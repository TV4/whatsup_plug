defmodule WhatsupTest do
  use ExUnit.Case
  use Plug.Test

  describe "init" do
    test "require credentials" do
      assert_raise ArgumentError, "credentials are missing", fn -> Whatsup.Plug.init([]) end
    end

    test "require framework" do
      assert_raise ArgumentError, "framework is missing", fn -> Whatsup.Plug.init(credentials: "user:password") end
    end

    test "valid init" do
      assert Whatsup.Plug.init(
               credentials: "user:password",
               framework: %{name: "framework", version: "1.2.3"}
             ) == [
               credentials: "user:password",
               framework: %{name: "framework", version: "1.2.3"},
               date_time: DateTime
             ]
    end
  end

  describe "call" do
    test "require authentication" do
      conn =
        conn(:get, "/__status")
        |> Whatsup.Plug.call(credentials: "user:password")

      assert json_response(conn, 401) == %{"error" => "Not authenticated"}
    end

    test "get status" do
      conn =
        conn(:get, "/__status")
        |> put_req_header("authorization", "Basic " <> Base.encode64("user:password"))
        |> Whatsup.Plug.call(
          credentials: "user:password",
          date_time: fn -> ~U[2019-10-04 14:02:07Z] end,
          framework: %{name: "framework", version: "1.2.3"}
        )

      assert json_response(conn, 200) == %{
               "date" => "2019-10-04T14:02:07Z",
               "framework" => %{"name" => "framework", "version" => "1.2.3"},
               "language" => %{"name" => "elixir", "version" => System.version()}
             }
    end
  end

  defp json_response(%Plug.Conn{resp_body: body, status: status_code}, status_code) do
    Jason.decode!(body)
  end

  defp json_response(%Plug.Conn{resp_body: body, status: status}, given) do
    raise "expected response with status #{given}, got: #{status}, with body:\n#{body}"
  end
end
