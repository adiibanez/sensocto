# SensOcto UI Patterns

## Design System

### Color Palette

```
Primary:     Blue (#3B82F6, blue-500)
Accent:      Amber (#F59E0B, amber-500)
Success:     Green (#22C55E, green-500)
Warning:     Yellow (#EAB308, yellow-500)
Error:       Red (#EF4444, red-500)

Background:  Gray-800 (#1F2937)
Surface:     Gray-700 (#374151)
Border:      Gray-600 (#4B5563)
Text:        White (#FFFFFF)
Text-muted:  Gray-400 (#9CA3AF)
```

### Typography

- **Font Stack**: System fonts (Inter preferred)
- **Headings**: Bold, tracking-tight
- **Body**: Normal weight
- **Code/Data**: Monospace

### Spacing Scale

```
xs:  0.25rem (4px)
sm:  0.5rem  (8px)
md:  0.75rem (12px)
lg:  1rem    (16px)
xl:  1.5rem  (24px)
2xl: 2rem    (32px)
```

## Layout Patterns

### 1. Dashboard Grid

```
┌─────────────────────────────────────────────┐
│  Header (fixed)                             │
├─────────────────────────────────────────────┤
│  ┌─────────┐ ┌─────────┐ ┌─────────┐       │
│  │ Sensor  │ │ Sensor  │ │ Sensor  │       │
│  │  Card   │ │  Card   │ │  Card   │       │
│  └─────────┘ └─────────┘ └─────────┘       │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐       │
│  │ Sensor  │ │ Sensor  │ │ Sensor  │       │
│  │  Card   │ │  Card   │ │  Card   │       │
│  └─────────┘ └─────────┘ └─────────┘       │
└─────────────────────────────────────────────┘
```

CSS: `grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4`

### 2. Sensor Detail View

```
┌─────────────────────────────────────────────┐
│  Header with back navigation                │
├─────────────────────────────────────────────┤
│  Sensor Name & Status                       │
├─────────────────────────────────────────────┤
│  ┌─────────────────────────────────────┐   │
│  │         Main Visualization          │   │
│  │           (ECG/IMU/Map)             │   │
│  └─────────────────────────────────────┘   │
├─────────────────────────────────────────────┤
│  ┌───────────┐ ┌───────────┐ ┌──────────┐  │
│  │  Metric   │ │  Metric   │ │  Metric  │  │
│  │   Card    │ │   Card    │ │   Card   │  │
│  └───────────┘ └───────────┘ └──────────┘  │
└─────────────────────────────────────────────┘
```

### 3. Room View with Call

```
┌─────────────────────────────────────────────┐
│  Room Header                     [Call BTN] │
├─────────────────────────────────────────────┤
│  ┌─────────────────────┐ ┌───────────────┐ │
│  │                     │ │   Members     │ │
│  │   Video Grid        │ │   ┌─────┐     │ │
│  │   (when in call)    │ │   │User1│     │ │
│  │                     │ │   └─────┘     │ │
│  │                     │ │   ┌─────┐     │ │
│  │                     │ │   │User2│     │ │
│  └─────────────────────┘ │   └─────┘     │ │
│                          └───────────────┘ │
├─────────────────────────────────────────────┤
│  Shared Sensors                             │
│  ┌─────────┐ ┌─────────┐                   │
│  │ Sensor  │ │ Sensor  │                   │
│  └─────────┘ └─────────┘                   │
└─────────────────────────────────────────────┘
```

### 4. Mobile SenseApp Toolbar

```
┌─────────────────────────────────────────────┐
│ [BLE] [IMU] [GPS] [BAT] [BTN] [PRES]       │
└─────────────────────────────────────────────┘
```

On desktop, expands to show device name input and autostart toggle.

## Component Patterns

### Sensor Card

```html
<div class="bg-gray-700 rounded-lg p-4 border border-gray-600">
  <!-- Header -->
  <div class="flex justify-between items-center mb-3">
    <h3 class="font-medium text-white">{sensor_name}</h3>
    <span class="status-indicator {status_class}"></span>
  </div>

  <!-- Mini Visualization -->
  <div class="h-24 mb-3">
    <MiniSparkline data={recent_values} />
  </div>

  <!-- Metrics Row -->
  <div class="flex justify-between text-sm">
    <span class="text-gray-400">Last value</span>
    <span class="text-white font-mono">{last_value}</span>
  </div>
</div>
```

### Metric Display

```html
<div class="text-center p-4">
  <div class="text-4xl font-bold text-white">{value}</div>
  <div class="text-sm text-gray-400">{unit}</div>
  <div class="text-xs text-amber-400">{label}</div>
</div>
```

### Status Indicator

```css
.status-indicator {
  width: 8px;
  height: 8px;
  border-radius: 50%;
}
.status-online { background-color: #22C55E; }
.status-offline { background-color: #6B7280; }
.status-error { background-color: #EF4444; }
.status-connecting {
  background-color: #F59E0B;
  animation: pulse 1.5s infinite;
}
```

### Button Variants

```html
<!-- Primary -->
<button class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded">
  Primary
</button>

<!-- Secondary -->
<button class="bg-gray-600 hover:bg-gray-500 text-white px-4 py-2 rounded">
  Secondary
</button>

<!-- Icon Button -->
<button class="p-2 rounded hover:bg-gray-600">
  <Icon name="bluetooth" class="w-5 h-5" />
</button>

<!-- Toggle Button (active state) -->
<button class="p-2 rounded bg-blue-600/20 text-blue-400">
  <Icon name="bluetooth" class="w-5 h-5" />
</button>
```

## Animation Patterns

### Heart Rate Pulse

```css
@keyframes heartbeat {
  0%, 100% { transform: scale(1); }
  50% { transform: scale(1.1); }
}

.heart-pulse {
  animation: heartbeat calc(60s / var(--bpm)) ease-in-out infinite;
}
```

### Loading States

```css
/* Skeleton loading */
.skeleton {
  background: linear-gradient(
    90deg,
    #374151 0%,
    #4B5563 50%,
    #374151 100%
  );
  background-size: 200% 100%;
  animation: shimmer 1.5s infinite;
}

@keyframes shimmer {
  0% { background-position: 200% 0; }
  100% { background-position: -200% 0; }
}
```

### Transition Patterns

```css
/* Smooth state transitions */
.transition-colors { transition: color 150ms, background-color 150ms; }
.transition-opacity { transition: opacity 200ms; }
.transition-transform { transition: transform 200ms; }

/* Accordion expand/collapse */
.accordion-content {
  max-height: 0;
  overflow: hidden;
  transition: max-height 300ms ease-out;
}
.accordion-content.expanded {
  max-height: 1000px;
}
```

## Responsive Breakpoints

```
sm:  640px   (mobile landscape)
md:  768px   (tablet)
lg:  1024px  (laptop)
xl:  1280px  (desktop)
2xl: 1536px  (large desktop)
```

### Mobile-First Patterns

```html
<!-- Stack on mobile, grid on desktop -->
<div class="flex flex-col md:flex-row gap-4">

<!-- Hide on mobile, show on desktop -->
<div class="hidden md:block">

<!-- Full width on mobile, constrained on desktop -->
<div class="w-full md:w-auto">

<!-- Smaller text on mobile -->
<span class="text-sm md:text-base">
```

## Accessibility Patterns

### Focus States

```css
button:focus-visible,
a:focus-visible,
input:focus-visible {
  outline: 2px solid #3B82F6;
  outline-offset: 2px;
}
```

### Screen Reader Support

```html
<!-- Hidden but accessible -->
<span class="sr-only">Sensor status: online</span>

<!-- ARIA labels -->
<button aria-label="Connect Bluetooth device">
  <Icon name="bluetooth" />
</button>

<!-- Live regions for updates -->
<div aria-live="polite" aria-atomic="true">
  Heart rate: {value} BPM
</div>
```

### Keyboard Navigation

- Tab through interactive elements
- Enter/Space to activate buttons
- Escape to close modals
- Arrow keys for dropdown navigation

## Data Visualization Guidelines

### Time-Series Charts (ECG, Pressure)

- **Line color**: Match attribute type (blue for ECG, amber for pressure)
- **Background**: Transparent or very dark
- **Axes**: Subtle gray, minimal labels
- **Grid lines**: Avoid or use very subtle
- **Animation**: Scroll left as new data arrives

### Gauges (Heart rate, Battery)

- **Arc gauges**: 180° or 270° sweep
- **Colors**: Gradient based on value (green → yellow → red)
- **Label**: Large center number with unit below

### 3D Visualizations (IMU)

- **Model**: Simple geometric shape (cube, arrow)
- **Rotation**: Smooth interpolation between updates
- **Lighting**: Ambient + directional for depth
- **Background**: Dark, minimal distractions

### Maps (Geolocation)

- **Tile style**: Dark mode map tiles
- **Marker**: Pulsing circle for current position
- **Track**: Semi-transparent line for path history
- **Controls**: Minimal, auto-hide
