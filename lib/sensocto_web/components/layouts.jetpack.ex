defmodule SensoctoWeb.Layouts.Jetpack do
  use SensoctoNative, [:layout, format: :jetpack]

  embed_templates "layouts_jetpack/*"
end
