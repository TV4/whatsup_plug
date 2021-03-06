defmodule Whatsup.Availability do
  @metrics_resolution 86400

  def percent(librato_user, librato_token, date_time, http_client) do
    [_, _, _, error_count] =
      counts =
      ["2xx", "3xx", "4xx", "5xx"]
      |> Enum.map(fn code ->
        Task.async(fn ->
          with {:ok, %HTTPoison.Response{body: body}} <-
                 http_client.get(
                   "https://metrics-api.librato.com/v1/metrics/router.status.#{code}?start_time=#{
                     DateTime.to_unix(date_time) - @metrics_resolution
                   }&end_time=#{DateTime.to_unix(date_time)}&resolution=#{@metrics_resolution}",
                   authorization: "Basic " <> Base.encode64(librato_user <> ":" <> librato_token)
                 ),
               {:ok, data} <- Jason.decode(body) do
            measurements = Map.get(data, "measurements")

            if map_size(measurements) == 0 do
              0
            else
              measurements
              |> Map.values()
              |> get_in([Access.at(0), Access.at(0), "count"])
            end
          else
            _ -> 0
          end
        end)
      end)
      |> Task.yield_many()
      |> Enum.map(fn
        {%Task{}, {:ok, result}} -> result
      end)

    with total when total > 0 <- Enum.sum(counts) do
      ((1 - error_count / total) * 100.0)
      |> Float.round(2)
    else
      _ -> 100.0
    end
    |> to_string()
  end
end

defmodule Whatsup.Plug do
  import Plug.Conn

  def init(options) do
    unless Keyword.has_key?(options, :credentials) do
      raise ArgumentError, "credentials are missing"
    end

    unless Keyword.has_key?(options, :framework) do
      raise ArgumentError, "framework is missing"
    end

    Keyword.merge([date_time: &DateTime.utc_now/0, http_client: HTTPoison], options)
  end

  def call(%Plug.Conn{request_path: "/__status"} = conn, options) do
    credentials = option(options, :credentials)

    with %Plug.Conn{halted: false} <- Plug.BasicAuth.basic_auth(conn, credentials) do
      data =
        %{
          date: now(options),
          framework: option(options, :framework),
          language: %{name: "elixir", version: System.version()}
        }
        |> append_service(options)
        |> append_environment(options)
        |> append_availability(options)

      conn
      |> put_resp_header("content-type", "application/json")
      |> send_resp(
        200,
        Jason.encode!(data)
      )
      |> halt
    end
  end

  def call(conn, _options), do: conn

  defp now(options) do
    option(options, :date_time)
  end

  defp append_service(data, options) do
    if service = option(options, :service) do
      Map.put(data, :service, service)
    else
      data
    end
  end

  defp append_environment(data, options) do
    if environment = option(options, :environment) do
      Map.put(data, :environment, environment)
    else
      data
    end
  end

  defp option(options, key) do
    Keyword.get(options, key)
    |> case do
      nil -> nil
      option when is_function(option) -> option.()
      option -> option
    end
  end

  defp append_availability(data, options) do
    librato_user = System.get_env("LIBRATO_USER")
    librato_token = System.get_env("LIBRATO_TOKEN")

    if librato_user && librato_token do
      data
      |> Map.put(
        "availability_percent",
        Whatsup.Availability.percent(
          librato_user,
          librato_token,
          option(options, :date_time),
          option(options, :http_client)
        )
      )
    else
      data
    end
  end
end
