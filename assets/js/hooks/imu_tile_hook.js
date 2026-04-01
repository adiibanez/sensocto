// ImuTileHook — updates IMU tile DOM elements from measurements-batch-event.
// After the ViewerDataChannel migration, data flows through JS only.
// IMU tiles are server-rendered HEEx (CSS transforms), so this hook
// bridges JS data events to DOM updates without a server round-trip.

function parseImuPayload(payload) {
  const defaults = {
    ax: 0, ay: 0, az: 0,
    pitch: 0, roll: 0, yaw: 0, heading: 0,
    accelMagnitude: 0,
    pitchDisplay: 0, rollDisplay: 0, tiltDisplay: 0,
  };

  if (payload == null) return defaults;

  // CSV string: timestamp,ax,ay,az,rx,ry,rz,qw,qx,qy,qz
  if (typeof payload === 'string') {
    const parts = payload.split(',').map(Number);
    if (parts.length >= 11) {
      const [, ax, ay, az, , , , qw, qx, qy, qz] = parts;
      const mag = Math.sqrt(ax * ax + ay * ay + az * az);
      const { pitch, roll, yaw } = quaternionToEuler(qw, qx, qy, qz);
      const heading = normalizeHeading(yaw);
      return {
        ax, ay, az,
        pitch, roll, yaw, heading,
        accelMagnitude: mag,
        pitchDisplay: clamp(pitch / 90 * 100, -100, 100),
        rollDisplay: clamp(roll / 90 * 100, -100, 100),
        tiltDisplay: clamp(roll / 2, -45, 45),
      };
    }
    return defaults;
  }

  // Object formats
  if (typeof payload === 'object') {
    // Quaternion: {w, x, y, z}
    if ('w' in payload && 'x' in payload && 'y' in payload && 'z' in payload &&
        !('accelerometer' in payload)) {
      const { pitch, roll, yaw } = quaternionToEuler(payload.w, payload.x, payload.y, payload.z);
      const heading = normalizeHeading(yaw);
      return {
        ...defaults,
        pitch, roll, yaw, heading,
        pitchDisplay: clamp(pitch / 90 * 100, -100, 100),
        rollDisplay: clamp(roll / 90 * 100, -100, 100),
        tiltDisplay: clamp(roll / 2, -45, 45),
      };
    }

    // Thingy:52 raw: {accelerometer: {x,y,z}, gyroscope: {x,y,z}}
    if (payload.accelerometer) {
      const a = payload.accelerometer;
      const ax = a.x || 0, ay = a.y || 0, az = a.z || 0;
      const mag = Math.sqrt(ax * ax + ay * ay + az * az);
      const pitch = Math.atan2(ax, Math.sqrt(ay * ay + az * az)) * 180 / Math.PI;
      const roll = Math.atan2(ay, az) * 180 / Math.PI;
      return {
        ax, ay, az,
        pitch, roll, yaw: 0, heading: 0,
        accelMagnitude: mag,
        pitchDisplay: clamp(pitch / 90 * 100, -100, 100),
        rollDisplay: clamp(roll / 90 * 100, -100, 100),
        tiltDisplay: clamp(roll / 2, -45, 45),
      };
    }

    // Puffer: {acc: {x,y,z}, gyro: {x,y,z}}
    if (payload.acc) {
      const a = payload.acc;
      const ax = a.x || 0, ay = a.y || 0, az = a.z || 0;
      const mag = Math.sqrt(ax * ax + ay * ay + az * az);
      const pitch = Math.atan2(ax, Math.sqrt(ay * ay + az * az)) * 180 / Math.PI;
      const roll = Math.atan2(ay, az) * 180 / Math.PI;
      return {
        ax, ay, az,
        pitch, roll, yaw: 0, heading: 0,
        accelMagnitude: mag,
        pitchDisplay: clamp(pitch / 90 * 100, -100, 100),
        rollDisplay: clamp(roll / 90 * 100, -100, 100),
        tiltDisplay: clamp(roll / 2, -45, 45),
      };
    }

    // Euler: {roll, pitch, yaw}
    if ('pitch' in payload && 'roll' in payload) {
      const { pitch, roll, yaw = 0 } = payload;
      const heading = normalizeHeading(yaw);
      return {
        ...defaults,
        pitch, roll, yaw, heading,
        pitchDisplay: clamp(pitch / 90 * 100, -100, 100),
        rollDisplay: clamp(roll / 90 * 100, -100, 100),
        tiltDisplay: clamp(roll / 2, -45, 45),
      };
    }
  }

  return defaults;
}

function quaternionToEuler(w, x, y, z) {
  const sinr_cosp = 2 * (w * x + y * z);
  const cosr_cosp = 1 - 2 * (x * x + y * y);
  const roll = Math.atan2(sinr_cosp, cosr_cosp) * 180 / Math.PI;

  const sinp = 2 * (w * y - z * x);
  const pitch = Math.abs(sinp) >= 1
    ? Math.sign(sinp) * 90
    : Math.asin(sinp) * 180 / Math.PI;

  const siny_cosp = 2 * (w * z + x * y);
  const cosy_cosp = 1 - 2 * (y * y + z * z);
  const yaw = Math.atan2(siny_cosp, cosy_cosp) * 180 / Math.PI;

  return { pitch, roll, yaw };
}

function normalizeHeading(yaw) {
  return ((yaw % 360) + 360) % 360;
}

function clamp(v, min, max) {
  return Math.max(min, Math.min(max, v));
}

const DIRECTIONS = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
function headingToDir(heading) {
  const idx = Math.round(((heading % 360) + 360) % 360 / 45) % 8;
  return DIRECTIONS[idx];
}

// Smooth green→yellow→orange→red gradient based on acceleration magnitude.
// Subtracts gravity (~9 m/s²) so stationary = green, vigorous motion = red.
function accelHsl(mag) {
  const excess = Math.max(mag - 9.0, 0);
  const t = Math.min(excess / 15.0, 1);
  const hue = 120 * (1 - t);
  return `hsl(${hue}, 80%, 50%)`;
}
function accelHslLight(mag) {
  const excess = Math.max(mag - 9.0, 0);
  const t = Math.min(excess / 15.0, 1);
  const hue = 120 * (1 - t);
  return `hsl(${hue}, 70%, 65%)`;
}

const IMU_AXIS_IDS = new Set([
  'accelerometer_x', 'accelerometer_y', 'accelerometer_z',
  'gyroscope_x', 'gyroscope_y', 'gyroscope_z',
  'imu', 'motion'
]);

export const ImuTileHook = {
  mounted() {
    this._sensorId = this.el.dataset.sensor_id;
    this._attrId = this.el.dataset.attribute_id;
    // Accumulated axis values for merging individual axes into one visualization
    this._axes = { ax: 0, ay: 0, az: 0, gx: 0, gy: 0, gz: 0 };

    this._onBatch = (e) => {
      const { sensor_id, attributes } = e.detail;
      if (sensor_id !== this._sensorId) return;

      // Check for a direct "imu" attribute (bundled CSV or merged payload)
      let directImu = null;
      let hasAxisUpdate = false;

      for (const a of attributes) {
        if (a.attribute_id === 'imu') {
          directImu = a;
        } else if (IMU_AXIS_IDS.has(a.attribute_id)) {
          hasAxisUpdate = true;
          const v = typeof a.payload === 'number' ? a.payload : 0;
          switch (a.attribute_id) {
            case 'accelerometer_x': this._axes.ax = v; break;
            case 'accelerometer_y': this._axes.ay = v; break;
            case 'accelerometer_z': this._axes.az = v; break;
            case 'gyroscope_x': this._axes.gx = v; break;
            case 'gyroscope_y': this._axes.gy = v; break;
            case 'gyroscope_z': this._axes.gz = v; break;
          }
        }
      }

      if (directImu) {
        this._updateDom(parseImuPayload(directImu.payload));
      } else if (hasAxisUpdate) {
        // Synthesize accelerometer/gyroscope object from accumulated axes
        const merged = {
          accelerometer: { x: this._axes.ax, y: this._axes.ay, z: this._axes.az },
          gyroscope: { x: this._axes.gx, y: this._axes.gy, z: this._axes.gz },
        };
        this._updateDom(parseImuPayload(merged));
      }
    };

    window.addEventListener('measurements-batch-event', this._onBatch);
  },

  _updateDom(d) {
    const el = this.el;

    // Phone icon rotation (summary)
    const phone = el.querySelector('[data-imu="phone"]');
    if (phone) phone.style.transform = `rotate(${d.tiltDisplay}deg)`;

    // Acceleration bar (summary)
    const accelBar = el.querySelector('[data-imu="accel-bar"]');
    if (accelBar) {
      accelBar.style.width = `${Math.min(100, Math.max(0, d.accelMagnitude - 9.0) / 15.0 * 100)}%`;
      accelBar.style.backgroundColor = accelHsl(d.accelMagnitude);
    }

    // Accel bar title (summary)
    const accelWrap = el.querySelector('[data-imu="accel-wrap"]');
    if (accelWrap) accelWrap.title = `Acceleration: ${d.accelMagnitude.toFixed(1)} m/s²`;

    // Tilt ball (summary — small sphere)
    const tiltBallSmall = el.querySelector('[data-imu="tilt-ball-small"]');
    if (tiltBallSmall) {
      tiltBallSmall.style.transform = `translate(${d.rollDisplay}%, ${d.pitchDisplay}%) translate(-50%, -50%)`;
    }

    // Tilt ball title
    const tiltWrap = el.querySelector('[data-imu="tilt-wrap"]');
    if (tiltWrap) tiltWrap.title = `Pitch: ${Math.round(d.pitch)}° Roll: ${Math.round(d.roll)}°`;

    // Compass arrow (summary)
    const compassArrow = el.querySelector('[data-imu="compass-arrow"]');
    if (compassArrow) compassArrow.style.transform = `rotate(${d.heading}deg)`;

    // Compass direction text (summary)
    const compassDir = el.querySelector('[data-imu="compass-dir"]');
    if (compassDir) compassDir.textContent = headingToDir(d.heading);

    // Compass title
    const compassWrap = el.querySelector('[data-imu="compass-wrap"]');
    if (compassWrap) compassWrap.title = `Heading: ${Math.round(d.heading)}°`;

    // Show data container, hide spinner
    const dataContainer = el.querySelector('[data-imu="data"]');
    if (dataContainer) dataContainer.style.display = '';
    const spinner = el.querySelector('[data-imu="spinner"]');
    if (spinner) spinner.style.display = 'none';

    // --- Expanded mode elements ---

    // Large tilt ball
    const tiltBall = el.querySelector('[data-imu="tilt-ball"]');
    if (tiltBall) {
      tiltBall.style.transform = `translate(${d.rollDisplay * 0.7}%, ${d.pitchDisplay * 0.7}%) translate(-50%, -50%)`;
    }

    // Large compass arrow
    const compassArrowLg = el.querySelector('[data-imu="compass-arrow-lg"]');
    if (compassArrowLg) compassArrowLg.style.transform = `translate(-50%, -50%) rotate(${d.heading}deg)`;

    // Heading text
    const headingText = el.querySelector('[data-imu="heading-text"]');
    if (headingText) headingText.textContent = `${Math.round(d.heading)}° ${headingToDir(d.heading)}`;

    // Accel magnitude
    const accelMag = el.querySelector('[data-imu="accel-mag"]');
    if (accelMag) {
      accelMag.textContent = d.accelMagnitude.toFixed(1);
      accelMag.style.color = accelHslLight(d.accelMagnitude);
    }

    // Euler angles
    const pitchVal = el.querySelector('[data-imu="pitch"]');
    if (pitchVal) pitchVal.textContent = `${d.pitch.toFixed(1)}°`;
    const rollVal = el.querySelector('[data-imu="roll"]');
    if (rollVal) rollVal.textContent = `${d.roll.toFixed(1)}°`;
    const yawVal = el.querySelector('[data-imu="yaw"]');
    if (yawVal) yawVal.textContent = `${d.yaw.toFixed(1)}°`;

    // Acceleration components
    const axVal = el.querySelector('[data-imu="ax"]');
    if (axVal) axVal.textContent = d.ax.toFixed(2);
    const ayVal = el.querySelector('[data-imu="ay"]');
    if (ayVal) ayVal.textContent = d.ay.toFixed(2);
    const azVal = el.querySelector('[data-imu="az"]');
    if (azVal) azVal.textContent = d.az.toFixed(2);
  },

  destroyed() {
    if (this._onBatch) {
      window.removeEventListener('measurements-batch-event', this._onBatch);
    }
  }
};
