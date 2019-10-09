defmodule Whatsup.Plug do
  import Plug.Conn

  def init(options) do
    unless Keyword.has_key?(options, :credentials) do
      raise ArgumentError, "credentials are missing"
    end

    unless Keyword.has_key?(options, :framework) do
      raise ArgumentError, "framework is missing"
    end

    Keyword.merge(options, date_time: &DateTime.utc_now/0, http_client: HTTPoison)
  end

  def call(%Plug.Conn{request_path: "/__status"} = conn, options) do
    credentials = options[:credentials][:username] <> ":" <> options[:credentials][:password]

    with ["Basic " <> auth] <- get_req_header(conn, "authorization"),
         true <- Plug.Crypto.secure_compare(credentials, Base.decode64!(auth)) do
      data =
        %{
          date: now(options),
          framework: options[:framework],
          language: %{name: "elixir", version: System.version()}
        }
        |> append_environment(options)
        |> append_availability(options)

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

  defp append_environment(data, options) do
    if Keyword.get(options, :environment) do
      Map.put(data, :environment, options[:environment].())
    else
      data
    end
  end

  defp append_availability(data, options) do
    librato_user = System.get_env("LIBRATO_USER")
    librato_token = System.get_env("LIBRATO_TOKEN")

    if librato_user && librato_token do
      [_, _, _, error_count] =
        counts =
        ["2xx", "3xx", "4xx", "5xx"]
        |> Enum.map(fn code ->
          {:ok, %HTTPoison.Response{body: body}} =
            options[:http_client].get(
              "https://metrics-api.librato.com/v1/metrics/router.status.#{code}?start_time=#{
                DateTime.to_unix(now(options)) - 86400
              }&end_time=#{now(options) |> DateTime.to_unix()}&resolution=86400",
              authorization:
                "Basic " <>
                  Base.encode64(librato_user <> ":" <> librato_token)
            )

          {:ok, data} = Jason.decode(body)

          measurements = Map.get(data, "measurements")

          if map_size(measurements) == 0 do
            0
          else
            measurements
            |> Map.values()
            |> get_in([Access.at(0), Access.at(0), "count"])
          end
        end)
        |> IO.inspect(label: :counts)

      availability =
        ((1 - error_count / Enum.sum(counts)) * 100.0)
        |> Float.round(2)
        |> to_string()

      data
      |> Map.put("availability_percent", availability)
    else
      data
    end
  end
end
