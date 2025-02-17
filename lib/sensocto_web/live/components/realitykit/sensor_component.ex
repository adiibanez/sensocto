defmodule SensoctoWeb.Live.Components.Swiftui.RealityKit.SensorComponent do
  use SensoctoNative, [:render_component, format: :swiftui]
  use Phoenix.LiveComponent

  use LiveViewNative.Component,
    format: :swiftui,
    as: :render

  require Logger

  def render(assigns, %{"target" => "watchos"}) do
    ~LVN"""
    <Text>Hello, from WatchOS!</Text>
    """
  end

  def render(assigns, _interface) do
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
end
