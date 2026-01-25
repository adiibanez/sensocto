defmodule SensoctoWeb.OpenApiTest do
  use SensoctoWeb.ConnCase, async: true

  describe "OpenAPI specification" do
    @tag :skip_unless_openapi_loaded
    test "GET /api/openapi returns valid JSON spec", %{conn: conn} do
      conn = get(conn, "/api/openapi")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"

      spec = json_response(conn, 200)

      # Verify OpenAPI 3.x structure
      assert spec["openapi"] =~ "3."
      assert spec["info"]["title"] == "Sensocto API"
      assert spec["info"]["version"] == "1.0.0"

      # Verify paths exist
      assert is_map(spec["paths"])
      assert Map.has_key?(spec["paths"], "/api/auth/verify")
      assert Map.has_key?(spec["paths"], "/api/rooms")
      assert Map.has_key?(spec["paths"], "/api/rooms/{id}")
      assert Map.has_key?(spec["paths"], "/health/live")

      # Verify security scheme
      assert spec["components"]["securitySchemes"]["bearerAuth"]["type"] == "http"
      assert spec["components"]["securitySchemes"]["bearerAuth"]["scheme"] == "bearer"
    end

    @tag :skip_unless_openapi_loaded
    test "GET /swaggerui returns HTML page", %{conn: conn} do
      conn = get(conn, "/swaggerui")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/html"
      assert conn.resp_body =~ "swagger-ui"
    end
  end
end
