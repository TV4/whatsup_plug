defmodule WhatsupTest do
  use ExUnit.Case
  use Plug.Test
  import Mox

  defmock(MockHTTPClient, for: HTTPoison.Base)

  setup :verify_on_exit!

  describe "init" do
    test "require credentials" do
      assert_raise ArgumentError, "credentials are missing", fn -> Whatsup.Plug.init([]) end
    end

    test "require framework" do
      assert_raise ArgumentError, "framework is missing", fn ->
        Whatsup.Plug.init(credentials: [username: "user", password: "pass"])
      end
    end

    test "valid init" do
      assert Whatsup.Plug.init(
               credentials: [username: "user", password: "pass"],
               framework: %{name: "framework", version: "1.2.3"}
             ) == [
               credentials: [username: "user", password: "pass"],
               framework: %{name: "framework", version: "1.2.3"},
               date_time: &DateTime.utc_now/0,
               http_client: HTTPoison
             ]
    end
  end

  describe "call" do
    test "require authentication" do
      conn =
        conn(:get, "/__status")
        |> Whatsup.Plug.call(credentials: [username: "user", password: "pass"])

      assert json_response(conn, 401) == %{"error" => "Not authenticated"}
    end

    test "get status" do
      conn =
        conn(:get, "/__status")
        |> put_req_header("authorization", "Basic " <> Base.encode64("user:pass"))
        |> Whatsup.Plug.call(
          credentials: [username: "user", password: "pass"],
          date_time: fn -> ~U[2019-10-04 14:02:07Z] end,
          framework: %{name: "framework", version: "1.2.3"}
        )

      assert json_response(conn, 200) == %{
               "date" => "2019-10-04T14:02:07Z",
               "framework" => %{"name" => "framework", "version" => "1.2.3"},
               "language" => %{"name" => "elixir", "version" => System.version()}
             }
    end

    test "availability percent" do
      on_exit(fn ->
        System.delete_env("LIBRATO_USER")
        System.delete_env("LIBRATO_TOKEN")
      end)

      System.put_env("LIBRATO_USER", "user@heroku.com")
      System.put_env("LIBRATO_TOKEN", "d34db33f")

      MockHTTPClient
      |> expect(
        :get,
        fn "https://metrics-api.librato.com/v1/metrics/router.status.2xx?start_time=1570111327&end_time=1570197727&resolution=86400",
           authorization: "Basic dXNlckBoZXJva3UuY29tOmQzNGRiMzNm" ->
          {:ok,
           %HTTPoison.Response{
             body: Jason.encode!(%{"measurements" => %{"app-name" => [%{"count" => 3}]}}),
             status_code: 200
           }}
        end
      )
      |> expect(
        :get,
        fn "https://metrics-api.librato.com/v1/metrics/router.status.3xx?start_time=1570111327&end_time=1570197727&resolution=86400",
           authorization: "Basic dXNlckBoZXJva3UuY29tOmQzNGRiMzNm" ->
          {:ok,
           %HTTPoison.Response{
             body: Jason.encode!(%{"measurements" => %{}}),
             status_code: 200
           }}
        end
      )
      |> expect(
        :get,
        fn "https://metrics-api.librato.com/v1/metrics/router.status.4xx?start_time=1570111327&end_time=1570197727&resolution=86400",
           authorization: "Basic dXNlckBoZXJva3UuY29tOmQzNGRiMzNm" ->
          {:ok,
           %HTTPoison.Response{
             body: Jason.encode!(%{"measurements" => %{"app-name" => [%{"count" => 1}]}}),
             status_code: 200
           }}
        end
      )
      |> expect(
        :get,
        fn "https://metrics-api.librato.com/v1/metrics/router.status.5xx?start_time=1570111327&end_time=1570197727&resolution=86400",
           authorization: "Basic dXNlckBoZXJva3UuY29tOmQzNGRiMzNm" ->
          {:ok,
           %HTTPoison.Response{
             body: Jason.encode!(%{"measurements" => %{"app-name" => [%{"count" => 1}]}}),
             status_code: 200
           }}
        end
      )

      conn =
        conn(:get, "/__status")
        |> put_req_header("authorization", "Basic " <> Base.encode64("user:pass"))
        |> Whatsup.Plug.call(
          credentials: [username: "user", password: "pass"],
          date_time: fn -> ~U[2019-10-04 14:02:07Z] end,
          framework: %{name: "framework", version: "1.2.3"},
          http_client: MockHTTPClient
        )

      assert json_response(conn, 200) == %{
               "availability_percent" => "80.0",
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
