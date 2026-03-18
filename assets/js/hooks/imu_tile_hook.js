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

function accelColorClass(mag) {
  if (mag < 2) return 'text-green-400 bg-green-500';
  if (mag < 5) return 'text-yellow-400 bg-yellow-500';
  if (mag < 10) return 'text-orange-400 bg-orange-500';
  return 'text-red-400 bg-red-500';
}

export const ImuTileHook = {
  mounted() {
    this._sensorId = this.el.dataset.sensor_id;
    this._attrId = this.el.dataset.attribute_id;

    this._onBatch = (e) => {
      const { sensor_id, attributes } = e.detail;
      if (sensor_id !== this._sensorId) return;

      // Find latest IMU measurement in this batch
      let latest = null;
      for (const a of attributes) {
        if (a.attribute_id === this._attrId) latest = a;
      }
      if (!latest) return;

      this._updateDom(parseImuPayload(latest.payload));
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
      accelBar.style.width = `${Math.min(100, d.accelMagnitude * 10)}%`;
      accelBar.className = `h-full rounded-full ${accelColorClass(d.accelMagnitude)}`;
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
      accelMag.className = `text-2xl font-bold ${accelColorClass(d.accelMagnitude)}`;
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
