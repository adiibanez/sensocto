// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = {
  content: [
    "./js/**/*.js",
    "./css/**/*.css",
    "../lib/sensocto_web.ex",
    "../lib/sensocto_web/**/*.*ex",
    "../deps/ash_authentication_phoenix/**/*.*ex",
    "../deps/daisy_ui_components/**/*.*ex",
    // "../deps/live_ex_webrtc/**/*.*ex"
  ],
  safelist: [
    // Ensure pulsating logo classes are never purged (used by JS hook)
    'pulsating-logo',
    'pulsing',
    // Dynamic button states (using custom 'orange' color, not orange-500 scale)
    'bg-orange',
    'hover:bg-hover-orange',
    'text-orange',
    'text-white',
  ],
  //purge: [
  //"../lib/sensocto_web/**/*.*ex",
  //"../lib/sensocto_web.ex",
  //"../lib/sensocto_web.ex",
  //"./svelte/**/*.svelte",
  //"../deps/ash_authentication_phoenix/**/*.*ex",
  //'./js/**/*.js',
  //],

  /*safelist: [
    'h-full', 'bg-gray-900', 'text-white', 'font-mono', 'flex-grow', 'overflow-y-auto',
    'bg-gray-800', 'p-4', 'flex', 'justify-between', 'items-center', 'h-12', 'w-auto',
    'text-gray-300', 'hover:text-white', 'mr-4',
    'container', 'mx-auto', 'p-4', 'grid', 'gap-4',
    'sm:gap-4', 'md:gap-4', 'lg:gap-4', 'xl:gap-4', 'grid-cols-1', 'sm:grid-cols-2',
    'lg:grid-cols-3', 'xl:grid-cols-6', '2xl:grid-cols-6',
    'hidden', 'bg-gray-800', 'p-4', 'rounded-lg', 'fixed', 'bottom-0', 'right-0', 'w-64', 'max-h-[80%]', 'overflow-y-auto',
    'btn', 'btn-blue',
    'fixed', 'top-2', 'right-2', 'mr-2', 'w-80', 'sm:w-96', 'z-50', 'rounded-lg', 'p-3', 'ring-1', 'bg-rose-50', 'text-rose-900', 'shadow-md', 'ring-rose-500',
    'opacity-40', 'group-hover:opacity-70',
    'flex', 'items-center', 'gap-1.5', 'text-sm', 'font-semibold', 'leading-6',
    'mt-2', 'text-sm', 'leading-5',
    'group', 'absolute', 'top-1', 'right-1', 'p-2',
    'animate-spin'
  ],*/
  theme: {
    extend: {
      screens: {
        'ultrawide': '2000px',
      },
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
    require("daisyui"),
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
