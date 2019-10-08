defmodule Whatsup.Plug do
  import Plug.Conn

  def init(options) do
    unless Keyword.has_key?(options, :credentials) do
      raise ArgumentError, "credentials are missing"
    end

    unless Keyword.has_key?(options, :framework) do
      raise ArgumentError, "framework is missing"
    end

    Keyword.merge(options, date_time: &DateTime.utc_now/0)
  end

  def call(%Plug.Conn{request_path: "/__status"} = conn, options) do
    credentials = options[:credentials][:username] <> ":" <> options[:credentials][:password]

    with ["Basic " <> auth] <- get_req_header(conn, "authorization"),
         true <- Plug.Crypto.secure_compare(credentials, Base.decode64!(auth)) do
      data = %{
        date: now(options),
        framework: options[:framework],
        language: %{name: "elixir", version: System.version()}
      }

      conn
      |> put_resp_header("content-type", "application/json")
      |> send_resp(
        200,
        Jason.encode!(data)
      )
      |> halt
    else
      _ ->
        conn
        |> put_resp_header("content-type", "application/json")
        |> send_resp(401, Jason.encode!(%{error: "Not authenticated"}))
        |> halt
    end
  end

  def call(conn, _options), do: conn

  defp now(options) do
    options[:date_time].()
  end
end
