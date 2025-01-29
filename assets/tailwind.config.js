// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/sensocto_web.ex",
    "../lib/sensocto_web/**/*.*ex",
    "../deps/ash_authentication_phoenix/**/*.*ex",
  ],
  theme: {
    extend: {
      colors: {
        brand: "#FD4F00",
        primary: {
          50: '#ffffff',
          100: '#ffffff',
          200: '#ffdecf',
          300: '#ffbb9c',
          400: '#ff9769',
          500: '#ff7436',
          600: '#ff5103',
          700: '#cf4000',
          800: '#9c3000',
          900: '#692000',
          950: '#4f1900'
        },
        'near-black': '#1a1a1a',
        'dark-gray': '#2b2b2b',
        'light-gray': '#f0f0f0',
        'medium-gray': '#999999',
        'orange': '#ffa500',
        'hover-orange': '#ffb347',
        'deep-blue': '#121b28',
        'medium-blue': '#1e2c3a',
        'coral': '#ff7f50',
        'hover-coral': '#ff9c74',
        'charcoal': '#222222',
        'dark-charcoal': '#2e2e2e',
        'off-white': '#f5f5f5',
        'amber': '#ffc107',
        'hover-amber': '#ffca3a',
        'slate': '#374151',
        'medium-slate': '#4b5563',
        'burnt-orange': '#e2725b',
        'hover-burnt-orange': '#e88b78',
      }
    },
  },
  plugins: [
    //require("@tailwindcss/forms"),
    // Allows prefixing tailwind classes with LiveView classes to add rules
    // only when LiveView classes are applied, for example:
    //
    //     <div class="phx-click-loading:animate-ping">
    //
    plugin(({ addVariant }) => addVariant("phx-no-feedback", [".phx-no-feedback&", ".phx-no-feedback &"])),
    plugin(({ addVariant }) => addVariant("phx-click-loading", [".phx-click-loading&", ".phx-click-loading &"])),
    plugin(({ addVariant }) => addVariant("phx-submit-loading", [".phx-submit-loading&", ".phx-submit-loading &"])),
    plugin(({ addVariant }) => addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"])),

    // Embeds Heroicons (https://heroicons.com) into your app.css bundle
    // See your `CoreComponents.icon/1` for more information.
    //
    plugin(function ({ matchComponents, theme }) {
      let iconsDir = path.join(__dirname, "../deps/heroicons/optimized")
      let values = {}
      let icons = [
        ["", "/24/outline"],
        ["-solid", "/24/solid"],
        ["-mini", "/20/solid"],
        ["-micro", "/16/solid"]
      ]
      icons.forEach(([suffix, dir]) => {
        fs.readdirSync(path.join(iconsDir, dir)).forEach(file => {
          let name = path.basename(file, ".svg") + suffix
          values[name] = { name, fullPath: path.join(iconsDir, dir, file) }
        })
      })
      matchComponents({
        "hero": ({ name, fullPath }) => {
          let content = fs.readFileSync(fullPath).toString().replace(/\r?\n|\r/g, "")
          let size = theme("spacing.6")
          if (name.endsWith("-mini")) {
            size = theme("spacing.5")
          } else if (name.endsWith("-micro")) {
            size = theme("spacing.4")
          }
          return {
            [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
            "-webkit-mask": `var(--hero-${name})`,
            "mask": `var(--hero-${name})`,
            "mask-repeat": "no-repeat",
            "background-color": "currentColor",
            "vertical-align": "middle",
            "display": "inline-block",
            "width": size,
            "height": size
          }
        }
      }, { values })
    })
  ]
}
