defmodule SensoctoWeb.Api.ConnectorController do
  @moduledoc """
  API controller for connector management.

  Provides REST endpoints for:
  - GET /api/connectors - list user's connectors
  - GET /api/connectors/:id - get connector with sensors
  - PUT /api/connectors/:id - update connector (rename)
  - DELETE /api/connectors/:id - forget a connector
  """
  use SensoctoWeb, :controller
  use OpenApiSpex.ControllerSpecs
  require Logger

  alias Sensocto.Sensors.{Connector, ConnectorManager}
  alias SensoctoWeb.Schemas.Common

  tags(["Connectors"])
  security([%{"bearerAuth" => []}])

  operation(:index,
    summary: "List user's connectors",
    description: "Lists all connectors belonging to the authenticated user.",
    responses: [
      ok:
        {"List of connectors", "application/json",
         SensoctoWeb.Schemas.ConnectorSchemas.ConnectorListResponse},
      unauthorized: {"Invalid or missing token", "application/json", Common.Error}
    ]
  )

  operation(:show,
    summary: "Get connector details",
    description: "Gets a connector by ID with its attached sensors.",
    parameters: [
      id: [in: :path, description: "Connector UUID", type: :string, required: true]
    ],
    responses: [
      ok:
        {"Connector details", "application/json",
         SensoctoWeb.Schemas.ConnectorSchemas.ConnectorResponse},
      unauthorized: {"Invalid or missing token", "application/json", Common.Error},
      not_found: {"Connector not found", "application/json", Common.Error}
    ]
  )

  operation(:update,
    summary: "Update connector",
    description: "Rename or update a connector. Users can only update their own connectors.",
    parameters: [
      id: [in: :path, description: "Connector UUID", type: :string, required: true]
    ],
    request_body:
      {"Connector update", "application/json",
       SensoctoWeb.Schemas.ConnectorSchemas.ConnectorUpdateRequest},
    responses: [
      ok:
        {"Updated connector", "application/json",
         SensoctoWeb.Schemas.ConnectorSchemas.ConnectorResponse},
      unauthorized: {"Invalid or missing token", "application/json", Common.Error},
      forbidden: {"Not your connector", "application/json", Common.Error},
      not_found: {"Connector not found", "application/json", Common.Error}
    ]
  )

  operation(:delete,
    summary: "Forget a connector",
    description: "Permanently remove a connector. Users can only forget their own connectors.",
    parameters: [
      id: [in: :path, description: "Connector UUID", type: :string, required: true]
    ],
    responses: [
      ok: {"Connector forgotten", "application/json", Common.Error},
      unauthorized: {"Invalid or missing token", "application/json", Common.Error},
      forbidden: {"Not your connector", "application/json", Common.Error},
      not_found: {"Connector not found", "application/json", Common.Error}
    ]
  )

  def index(conn, _params) do
    case get_current_user(conn) do
      {:ok, user} ->
        connectors = ConnectorManager.list_for_user(user.id)
        json(conn, %{connectors: Enum.map(connectors, &connector_to_json/1)})

      {:error, reason} ->
        conn |> put_status(:unauthorized) |> json(%{error: reason})
    end
  end

  def show(conn, %{"id" => id}) do
    case get_current_user(conn) do
      {:ok, _user} ->
        case Connector
             |> Ash.Query.for_read(:get_with_sensors, %{id: id})
             |> Ash.read_one() do
          {:ok, nil} ->
            conn |> put_status(:not_found) |> json(%{error: "Connector not found"})

          {:ok, connector} ->
            json(conn, %{connector: connector_to_json(connector)})

          {:error, _} ->
            conn |> put_status(:not_found) |> json(%{error: "Connector not found"})
        end

      {:error, reason} ->
        conn |> put_status(:unauthorized) |> json(%{error: reason})
    end
  end

  def update(conn, %{"id" => id} = params) do
    case get_current_user(conn) do
      {:ok, user} ->
        case ConnectorManager.get(id) do
          {:ok, connector} ->
            if to_string(connector.user_id) == to_string(user.id) do
              case connector
                   |> Ash.Changeset.for_update(:rename, %{name: params["name"]})
                   |> Ash.update() do
                {:ok, updated} ->
                  json(conn, %{connector: connector_to_json(updated)})

                {:error, error} ->
                  conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(error)})
              end
            else
              conn |> put_status(:forbidden) |> json(%{error: "Not your connector"})
            end

          {:error, :not_found} ->
            conn |> put_status(:not_found) |> json(%{error: "Connector not found"})
        end

      {:error, reason} ->
        conn |> put_status(:unauthorized) |> json(%{error: reason})
    end
  end

  def delete(conn, %{"id" => id}) do
    case get_current_user(conn) do
      {:ok, user} ->
        case ConnectorManager.get(id) do
          {:ok, connector} ->
            if to_string(connector.user_id) == to_string(user.id) do
              case Ash.destroy(connector, action: :forget, actor: user) do
                :ok ->
                  json(conn, %{ok: true, message: "Connector forgotten"})

                {:error, error} ->
                  conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(error)})
              end
            else
              conn |> put_status(:forbidden) |> json(%{error: "Not your connector"})
            end

          {:error, :not_found} ->
            conn |> put_status(:not_found) |> json(%{error: "Connector not found"})
        end

      {:error, reason} ->
        conn |> put_status(:unauthorized) |> json(%{error: reason})
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp get_current_user(conn) do
    auth_header = Plug.Conn.get_req_header(conn, "authorization")

    token =
      case auth_header do
        ["Bearer " <> t] -> t
        [t] -> t
        _ -> nil
      end

    if token do
      case AshAuthentication.Jwt.verify(token, Sensocto.Accounts.User) do
        {:ok, %{"sub" => _} = claims, _resource} ->
          load_user_from_subject(claims["sub"])

        {:ok, %{id: _} = user, _claims} ->
          {:ok, user}

        {:ok, %{id: _} = user} ->
          {:ok, user}

        {:ok, %{"sub" => _} = claims} ->
          load_user_from_subject(claims["sub"])

        _ ->
          {:error, "Invalid token"}
      end
    else
      {:error, "Missing authorization header"}
    end
  end

  defp load_user_from_subject(sub) do
    case Regex.run(~r/id=([a-f0-9-]+)/i, sub || "") do
      [_, id] -> Ash.get(Sensocto.Accounts.User, id)
      _ -> {:error, "Invalid subject"}
    end
  end

  defp connector_to_json(connector) do
    base = %{
      id: connector.id,
      name: connector.name,
      connector_type: connector.connector_type,
      status: connector.status,
      configuration: connector.configuration,
      last_seen_at: connector.last_seen_at,
      connected_at: connector.connected_at,
      inserted_at: connector.inserted_at,
      updated_at: connector.updated_at
    }

    # Include sensors if loaded
    case Map.get(connector, :sensors) do
      %Ash.NotLoaded{} -> base
      nil -> base
      sensors -> Map.put(base, :sensors, Enum.map(sensors, &sensor_to_json/1))
    end
  end

  defp sensor_to_json(sensor) do
    %{
      id: sensor.id,
      sensor_id: sensor.sensor_id,
      sensor_name: sensor.sensor_name,
      sensor_type: Map.get(sensor, :sensor_type)
    }
  end
end
