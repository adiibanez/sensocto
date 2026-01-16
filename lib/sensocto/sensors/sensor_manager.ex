defmodule Sensocto.Sensors.SensorManager do
  @moduledoc false
  use Ash.Resource,
    domain: Sensocto.Sensors,
    # data_layer: Ash.DataLayer.Simple,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    # AshAuthentication,
    extensions: [AshAdmin.Resource]

  actions do
    # Step 1: Validate input data
    create :validate_sensor do
      accept [
        :sensor_id,
        :connector_id,
        :connector_name,
        :sensor_name,
        :sensor_name,
        :sensor_type
      ]

      # argument :sensor_id, :string, allow_nil?: false
      # argument :connector_id, :string, allow_nil?: false
      # argument :connector_name, :string, allow_nil?: false
      # argument :sensor_name, :string, allow_nil?: false
      # argument :sensor_type, :string, allow_nil?: false

      # %{sensor_id: "8a2d48778e4a", connector_name: "MacIntel_Chrome", connector_id: "8a2d48778e4a", sensor_name: "MacIntel_Chrome", sensor_type: "html5"}

      # validate fn changeset, _ ->
      #   required_fields = [:sensor_id, :connector_id, :connector_name, :sensor_name, :sensor_type]

      #   missing_fields =
      #     required_fields
      #     |> Enum.filter(&is_nil(Ash.Changeset.get_argument(changeset, &1)))

      #   if missing_fields == [] do
      #     changeset
      #   else
      #     Ash.Changeset.add_error(changeset, :validation, "Missing required fields: #{inspect(missing_fields)}")
      #   end
      # end
    end

    # Step 2: Lookup existing sensor process
    read :get_sensor do
      argument :sensor_id, :string, allow_nil?: false

      # validate fn changeset, _ ->
      #   sensor_id = Ash.Changeset.get_argument(changeset, :sensor_id)

      #   case Sensocto.SensorsDynamicSupervisor.lookup_sensor(sensor_id) do
      #     {:ok, _pid} -> changeset
      #     {:error, :not_found} -> Ash.Changeset.add_error(changeset, :sensor_id, "Sensor not found")
      #   end
      # end
    end

    # Step 3: Stop a sensor
    update :stop_sensor do
      require_atomic? false
      argument :sensor_id, :string, allow_nil?: false

      change fn changeset, _ ->
        sensor_id = Ash.Changeset.get_argument(changeset, :id)

        case Sensocto.SensorsDynamicSupervisor.stop_sensor(sensor_id) do
          :ok ->
            changeset

          {:error, reason} ->
            Ash.Changeset.add_error(
              changeset,
              :sensor_id,
              "Failed to stop sensor: #{inspect(reason)}"
            )
        end
      end
    end
  end

  # extensions: [Ash.Resource.Dsl],

  # validate_domain_inclusion?: true,
  # primary_read_warning?: true,
  # embed_nil_values?: true,
  # authorizers: [],
  # notifiers: [],

  # require_primary_key? false

  policies do
    # Anything you can use in a condition, you can use in a check, and vice-versa
    # This policy applies if the actor is a super_user
    # Additionally, this policy is declared as a `bypass`. That means that this check is allowed to fail without
    # failing the whole request, and that if this check *passes*, the entire request passes.
    bypass actor_attribute_equals(:super_user, true) do
      authorize_if always()
    end

    # This will likely be a common occurrence. Specifically, policies that apply to all read actions
    policy action_type(:read) do
      # unless the actor is an active user, forbid their request
      # forbid_unless actor_attribute_equals(:active, true)
      # if the record is marked as public, authorize the request
      # authorize_if attribute(:public, true)
      # if the actor is related to the data via that data's `owner` relationship, authorize the request
      # authorize_if relates_to_actor_via(:owner)
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if always()
    end

    policy action_type(:update) do
      authorize_if always()
    end
  end

  validations do
    # Ensure required fields are present when creating a sensor
    validate present([:sensor_id, :connector_id, :connector_name, :sensor_name, :sensor_type]),
      on: :create

    # validate present([:sensor_name, :sensor_type, :connector_name], at_least: 2), on: :update
    # validate absent([:sensor_name, :sensor_type, :connector_name], exactly: 1), on: :destroy
  end

  attributes do
    uuid_primary_key :id
    attribute :sensor_id, :string, allow_nil?: false
    attribute :connector_id, :string, allow_nil?: false
    attribute :connector_name, :string, allow_nil?: false
    attribute :sensor_name, :string, allow_nil?: false
    attribute :sensor_type, :string, allow_nil?: true
  end
end
