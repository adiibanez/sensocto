defmodule SensoctoWeb.RealitykitLive.SwiftUI do
  use SensoctoNative, [:render_component, format: :swiftui]
  require Logger
  # alias SensoctoWeb.Live.Components.SensorComponent.SwiftUI

  def render(assigns, interface) do
    Logger.debug(
      "SWIFT render pid: #{inspect(self())} #{inspect(interface)} #{inspect(assigns.config.rotation)}"
    )

    Nx.to_list(Quaternion.euler(-:math.pi() / 2, :math.pi() / 2 * assigns.config.rotation, 0))
    # |> dbg()

    # Enum.all?(assigns[:sensors], fn {sensor_id, sensor} ->
    #   Logger.debug(
    #     "SWIFT Sensor: #{sensor_id} #{inspect(sensor.translation)} #{is_float(sensor.translation.x)} #{is_integer(sensor.translation.x)}"
    #   )
    # end)

    #  <SimpleMaterial
    #   template="materials"
    #   color="system-red"
    # />

    # https://medium.com/better-programming/introduction-to-realitykit-on-ios-entities-gestures-and-ray-casting-8f6633c11877

    ~LVN"""

    <RealityView  audibleClicks id="reality_view_2" phx-click="test_event_realityview" phx-change="test_event_realityview" counter={@counter}>


      <Entity
      id="world"
      test={@config.rotation}
      transform:rotation={Nx.to_list(Quaternion.euler(0, :math.pi / 2 * @config.rotation, 0))}
      transform:duration={1}
      cameraTarget
    >

    <.sensor :for={{sensor_id, sensor} <- @sensors}
      scale={@config.scale}
      id={sensor_id}
      sensor_id={sensor_id}
      sensor={sensor}
      config={@config}>
    </.sensor>

    <!--<.live_component  module={SensorComponent} :for={{sensor_id, sensor} <- @sensors}
      scale={@config.scale}
      id={sensor_id}
      sensor_id={sensor_id}
      sensor={sensor}
      config={@config}>

    </.live_component>-->

    <Group template="components">
    <OpacityComponent opacity={1.0}  id={"opacity_component"} />
    <CollisionComponent  id={"collision_component"} phx-click="test_collision_component" phx-change="collision_change"/>
      <PhysicsBodyComponent mass="0.5"  id={"physics_body_component"} phx-click="test_physics_body_component" phx-change="test_physics_body_component"/>
      <GroundingShadowComponent  id={"grouping_shadow_component"} castsShadow />
      <%!--<AnchoringComponent id={"anchor"} target="plane" alignment="vertical" classification="wall" />--%>
    </Group>



    </Entity>

    </RealityView>
    """
  end

  def sensor(assigns, _interface) do
    ~LVN"""
    <Group>

    <Attachment id={"attachment_#{@sensor_id}"} template="attachments">
              <HStack style="buttonStyle(.plain); padding(8); glassBackgroundEffect();">
              <Text>Hello {@sensor_id}</Text>
                <Button phx-click="rotate">
                  <Image systemName="arrow.2.circlepath.circle.fill" style="imageScale(.large); symbolRenderingMode(.hierarchical);" />
                </Button>
              </HStack>
              </Attachment>
              <ViewAttachmentEntity
              attachment={"attachment_#{@sensor_id}"}
              transform:translation={[@sensor.translation.x, @sensor.translation.y, @sensor.translation.z + 0.1]}
              transform:rotation={Nx.to_list(Quaternion.euler(-:math.pi / 2, 0, 0))}
              />

    <ModelEntity  id={"model_entity_#{@sensor_id}"}
      transform:translation={[@sensor.translation.x, @sensor.translation.y, @sensor.translation.z]}
       transform:rotation={[@sensor.rotation.x, @sensor.rotation.y, @sensor.rotation.z, @sensor.rotation.angle]}
      generateCollisionShapes="recursive"
      phx-change="model_change"
      phx-click="model_tapped"
      phx-value-sensor_id={@sensor_id}
      >

      <Sphere id={"box_#{@sensor_id}"}
      template="mesh"
      radius={@sensor.size}
      phx-change="box_change"
      phx-click="box_tapped"
      phx-value-sensor_id={@sensor_id}>
    ></Sphere>

    <SimpleMaterial
    id={"material_#{@sensor_id}"}
      template="materials"
      color={"system-#{@sensor.color}"}
    />

    <%!--


    <Box id={"box_#{@sensor_id}"}
      template="mesh"
      size={@sensor.size}
      phx-change="box_change"
      phx-click="box_tapped"
      phx-value-sensor_id={@sensor_id}>
    ></Box>


    style="onAppear(perform: animateWithSpringEffect)"


    <PhysicallyBasedMaterial
     id={"physics_base_material_#{@sensor_id}"}
    template="materials"
    baseColor={"system-#{@sensor.color}"}
    metallic={0.6}
    roughness={0.3}
    />--%>

    <Group template="components">
    <OpacityComponent opacity={0.8}  id={"opacity_component_#{@sensor_id}"} />
    </Group>
    </ModelEntity>
    </Group>
    """
  end

  attr :color, :any

  def palette(assigns, _interface) do
    # assigns |> dbg()

    ~LVN"""
    <HStack style="buttonStyle(.plain); padding(8); glassBackgroundEffect();">
      <Button phx-click="rotate">
        <Image systemName="arrow.2.circlepath.circle.fill" style="imageScale(.large); symbolRenderingMode(.hierarchical);" />
      </Button>
      <Button
        :for={color <- ["system-red", "system-orange", "system-yellow", "system-green", "system-mint", "system-teal", "system-cyan", "system-blue", "system-indigo", "system-purple", "system-pink", "system-brown", "system-white", "system-gray", "system-black"]}
        phx-click="pick-color"
        phx-value-color={color}
      >
        <ZStack style="frame(width: 24, height: 24)">
          <Circle class={color} />
          <Circle :if={@color == color} style="stroke(.white, lineWidth: 4)" />
        </ZStack>
      </Button>
      <Button
        phx-click="pick-color"
        phx-value-color="delete"
        style="foregroundStyle(.white);"
      >
        <ZStack style="frame(width: 24, height: 24)">
          <Image
            systemName="eraser.fill"
            style="resizable(); scaledToFill(); padding(4); background(.red, in: .circle);"
          />
          <Circle :if={@color == nil} style="stroke(.white, lineWidth: 3)" />
        </ZStack>
      </Button>
    </HStack>
    """
  end
end
