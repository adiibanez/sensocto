# Reuss River Monitoring — API Research Report

Research report for integrating live hydrological data from the Reuss river (Switzerland) into Sensocto's Reuss Initiative room.

---

## 1. Available Data Sources

### Existenz.ch API (Recommended Primary)

- **URL**: `https://api.existenz.ch/apiv1/hydro/`
- **Type**: REST/JSON, no authentication required
- **Refresh**: 10-minute measurement intervals
- **Docs**: OpenAPI spec at `https://api.existenz.ch/openapi/apiv1.yaml`, Swagger UI at `https://api.existenz.ch/docs/apiv1`
- **Test server**: `https://api-test.existenz.ch/apiv1`
- **Metadata**: Browseable via Datasette at `https://api-datasette.konzept.space/existenz-api/hydro_locations`
- **Why recommended**: Simplest integration path — clean JSON payloads, no auth, well-documented OpenAPI spec, health endpoint for monitoring freshness.

### BAFU Hydrodaten Portal

- **URL**: `https://www.hydrodaten.admin.ch`
- **Type**: Official Swiss Federal Office for the Environment (FOEN/BAFU) portal
- **Access**: Web-based charts (40-day history), data tables (current year), SMS alerts, FTP for bulk data
- **Limitations**: No clean REST API for programmatic access. Designed for human consumption and bulk data orders.
- **Use case**: Reference/validation source, not primary integration target.

### LINDAS SPARQL (Linked Data)

- **URL**: `https://lindas.admin.ch/sparql/`
- **Dataset**: `https://environment.ld.admin.ch/.well-known/void/dataset/hydro`
- **Type**: RDF/SPARQL endpoint, 10-minute updates
- **Access**: Open, no authentication
- **Limitations**: SPARQL queries are more complex to construct and maintain than REST calls. Better suited for semantic queries across multiple datasets than for simple time-series polling.
- **Use case**: Potential secondary source or for enriching station metadata with linked data.

---

## 2. Reuss River Stations

Four BAFU monitoring stations along the Reuss, from alpine source to lowland:

| Station ID | Name | Lat | Lon | CHX | CHY | Elevation Context |
|------------|------|-----|-----|-----|-----|-------------------|
| **2087** | Andermatt | 46.6423°N | 8.5896°E | 688120 | 166320 | Alpine source (~1427m, from height readings) |
| **2056** | Seedorf | 46.8839°N | 8.6206°E | 690085 | 193210 | Upper valley (~437m) |
| **2152** | Luzern, Geissmattbrücke | 47.0540°N | 8.2985°E | 665330 | 211800 | Lake outlet (~431m) |
| **2018** | Mellingen | 47.4210°N | 8.2713°E | 662830 | 252580 | Lowland (~344m) |

The stations span ~90km of the Reuss from the Gotthard region to the Aargau lowlands, providing a longitudinal profile of the river's conditions.

---

## 3. Parameter Availability Matrix

Parameters confirmed available per station (via live API query):

| Parameter | Unit | 2087 Andermatt | 2056 Seedorf | 2152 Luzern | 2018 Mellingen |
|-----------|------|:--------------:|:------------:|:-----------:|:--------------:|
| **height** | m a.s.l. | Y | Y | Y | Y |
| **flow** | m³/s | Y | Y | Y | Y |
| **temperature** | °C | — | Y | Y | Y |
| **turbidity** | BSTU | — | Y | — | — |
| **oxygen** | mg/l | — | — | — | Y |
| **acidity** | pH | — | — | — | Y |
| **conductivity** | µS/cm | — | — | — | Y |

**Notes**:
- All 4 stations provide height and flow. Temperature is available at 3 of 4.
- Mellingen (2018) is the most instrumented station with 6 parameters including water quality.
- Andermatt (2087) is the most limited — height and flow only (alpine conditions).
- Additional parameters may appear seasonally or after station upgrades.

### Full Parameter Reference (all BAFU hydro parameters)

| API Name | Description | Unit |
|----------|-------------|------|
| `temperature` | Water temperature | °C |
| `flow` | Discharge | m³/s |
| `flow-liters` | Discharge (small streams) | l/s |
| `height` | Water level above sea level | m a.s.l. |
| `height-absolute` | Water level (gauge reading) | m |
| `oxygen` | Dissolved oxygen | mg/l |
| `acidity` | pH value | pH |
| `conductivity` | Electrical conductivity | µS/cm |
| `turbidity` | Turbidity | BSTU |

---

## 4. Existenz.ch API Reference

### Endpoints

#### `GET /apiv1/hydro/locations`
Station metadata for all ~243 BAFU hydrology stations.

```
GET https://api.existenz.ch/apiv1/hydro/locations?app=sensocto
```

Returns array of station objects with `station_id`, `name`, `water_body_name`, `water_body_type`, `lat`, `lon`, `chx`, `chy`, `link`.

#### `GET /apiv1/hydro/parameters`
All available measurement parameter types.

```
GET https://api.existenz.ch/apiv1/hydro/parameters?app=sensocto
```

#### `GET /apiv1/hydro/latest`
Latest measured values for specified stations and parameters.

```
GET https://api.existenz.ch/apiv1/hydro/latest?locations=2087,2056,2152,2018&parameters=temperature,flow,height&app=sensocto
```

**Query parameters**:
- `locations` — comma-separated station IDs (e.g., `2087,2056,2152,2018`)
- `parameters` — comma-separated parameter names (e.g., `temperature,flow,height`)
- `timeseriesformat` — response structure variant: `default`, `table`, `rows`, `array-per-location`, `table-per-location`
- `app` — application identifier (recommended: `sensocto`)
- `version` — API version (optional)

**Response** (default format):
```json
{
  "source": "Swiss Federal Office for the Environment FOEN / BAFU, Hydrology",
  "apiurl": "https://api.existenz.ch",
  "opendata": "https://opendata.swiss/...",
  "license": "https://www.hydrodaten.admin.ch/...",
  "payload": [
    {"timestamp": 1772661600, "loc": "2018", "par": "height", "val": 344.01},
    {"timestamp": 1772661600, "loc": "2018", "par": "flow", "val": 76.01},
    {"timestamp": 1772661600, "loc": "2018", "par": "temperature", "val": 7.51},
    {"timestamp": 1772661600, "loc": "2056", "par": "flow", "val": 11.79},
    {"timestamp": 1772661600, "loc": "2056", "par": "temperature", "val": 4.95},
    {"timestamp": 1772661600, "loc": "2152", "par": "height", "val": 431.03},
    {"timestamp": 1772661600, "loc": "2152", "par": "flow", "val": 54.31}
  ]
}
```

**Payload fields**:
- `timestamp` — Unix epoch seconds (UTC)
- `loc` — Station ID as string
- `par` — Parameter name (matches `/hydro/parameters` values)
- `val` — Measured value as float

#### `GET /apiv1/hydro/daterange`
Historical time-series data.

```
GET https://api.existenz.ch/apiv1/hydro/daterange?locations=2152&parameters=temperature&startdate=-24+hours&enddate=now&app=sensocto
```

**Additional query parameters**:
- `startdate` — UTC, supports PHP date formats (e.g., `2025-01-15`, `-24 hours`, `-7 days`). Default: `now`
- `enddate` — UTC, same format. Default: `-24 hours`
- Maximum range: ~32 days per request

**Note**: `startdate` and `enddate` naming is counterintuitive — `startdate` is the more recent bound and `enddate` is the older bound by default.

#### `GET /apiv1/hydro/health`
Data freshness check.

```
GET https://api.existenz.ch/apiv1/hydro/health?app=sensocto
```

**Responses**:
- `200 OK` — Recent data available (< 1 hour old)
- `503 Service Unavailable` — No recent values found

### Usage Guidelines

- **Polling**: 5-minute minimum recommended interval (data updates every 10 minutes)
- **App identifier**: Add `&app=sensocto` to all requests for tracking
- **Rate limits**: Not formally documented in the OpenAPI spec, but respectful polling is expected
- **Gaps**: 10-min periodicity; gaps and delays on individual stations/parameters are always possible

---

## 5. License & Attribution

- **Source**: Swiss Federal Office for the Environment (FOEN/BAFU)
- **License**: BAFU open data — free of charge for standard use
- **Attribution required**: All usage must credit FOEN/BAFU as the data source
- **Terms**: [BAFU Terms and Conditions for hydrological data (PDF)](https://www.bafu.admin.ch/bafu/en/home/topics/water/state/data/obtaining-monitoring-data-on-the-topic-of-water/hydrological-data-service-for-watercourses-and-lakes.html)
- **Existenz.ch**: Third-party mirror/API; the `license` field in API responses links to the official BAFU terms

---

## 6. Integration Architecture

### MVP Implementation (Simulator Scenario)

The Reuss river integration reuses the existing simulator infrastructure with a new `sensor_type: "hydro_api"`. This avoids building a new supervision tree and lets us show data immediately via the `/simulator` UI.

**Files**:
- `config/simulator_scenarios/reuss_river.yaml` — scenario definition
- `lib/sensocto/simulator/data_generator.ex` — added `hydro_api` case

### How It Works

Each BAFU parameter becomes an `AttributeServer` with `sensor_type: "hydro_api"`. Instead of generating synthetic data, `DataGenerator.fetch_hydro_api_data/1` calls the existenz.ch API:

```
GET https://api.existenz.ch/apiv1/hydro/latest
  ?locations=2152&parameters=temperature&app=sensocto
```

The `sampling_rate: 0.00333` (~1/300 Hz) means the AttributeServer schedules its next poll 5 minutes after each fetch. On API failure, a nil payload is returned and the 5-minute cycle continues.

**Data flow** (unchanged from other simulator sensors):
```
AttributeServer (hydro_api fetch) → SensorServer → SimpleSensor
  → AttributeStoreTiered → PubSub → Router → PriorityLens → LiveView
```

### Sensor/Attribute Mapping

| Sensor ID | Attributes |
|-----------|------------|
| `reuss-2087-andermatt` | height, flow |
| `reuss-2056-seedorf` | height, flow, temperature, turbidity |
| `reuss-2152-luzern` | height, flow, temperature |
| `reuss-2018-mellingen` | height, flow, temperature, oxygen, acidity, conductivity |

### Usage

1. Go to `/simulator`
2. Select scenario **reuss_river**
3. Sensors appear immediately; each attribute fetches its first value on startup
4. Assign sensors to the Reuss Initiative room via the room management UI

### YAML Config Key Fields

```yaml
sensor_type: "hydro_api"    # triggers API fetch instead of synthetic data
hydro_station_id: "2152"    # BAFU station ID
hydro_parameter: "temperature"  # parameter name matching existenz.ch API
sampling_rate: 0.00333      # controls poll interval (~5 min)
batch_window: 300000        # flush timer (5 min), aligned with sampling_rate
```

### Resilience

- **API failure**: Returns nil payload, maintains 5-minute retry cycle. Sensors retain last known values in AttributeStoreTiered.
- **Timeout**: 15s HTTP timeout per attribute request to avoid blocking.
- **Supervisor restart**: Standard simulator restart behavior — ConnectorServer restarts all AttributeServers if the connector crashes.
- **No data for parameter**: API returns empty payload; nil stored, logged as warning.

### Future Refactoring

The simulator approach works for MVP but carries the simulator's conceptual overhead (it appears in the simulator UI, uses simulator infrastructure designed for synthetic data). A dedicated `Sensocto.EcoMonitor` supervision tree would be cleaner long-term:

```
Application Supervisor
└── Sensocto.EcoMonitor.Supervisor (rest_for_one)
    ├── EcoMonitor.Registry
    └── EcoMonitor.HydroSupervisor (one_for_one)
        └── HydroPoller {:reuss, config}  — decoupled sensor lifecycle from polling
```

Key improvement: sensor processes outlive poller restarts (network errors don't take sensors offline), and the system is invisible to the simulator UI. The existenz.ch API also provides SwissMetNet weather data (`/apiv1/smn/`) with the same payload structure, making weather integration a natural next step.
