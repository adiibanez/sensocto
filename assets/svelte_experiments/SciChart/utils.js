export class Radix2FFT {
    constructor(size) {
        this.size = size;
        this.bitReverse = new Uint32Array(size);
        for (let i = 0; i < size; i++) {
            let rev = 0;
            for (let j = 0, k = size >> 1; j < Math.log2(size); j++, k >>= 1) {
                if (i & k) {
                    rev |= 1 << j;
                }
            }
            this.bitReverse[i] = rev;
        }
    }
    run(data) {
        const buffer = new Float32Array(this.size * 2);
        for (let i = 0; i < this.size; i++) {
            buffer[this.bitReverse[i] * 2] = data[i];
        }
        for (let i = 1; i < this.size; i *= 2) {
            for (let j = 0; j < this.size; j += i * 2) {
                for (let k = 0; k < i; k++) {
                    const even = (j + k) * 2;
                    const odd = (j + k + i) * 2;
                    const temp = buffer[odd] * Math.cos(Math.PI / i * k) - buffer[odd + 1] * Math.sin(Math.PI / i * k);
                    const temp2 = buffer[odd] * Math.sin(Math.PI / i * k) + buffer[odd + 1] * Math.cos(Math.PI / i * k);
                    buffer[odd] = buffer[even] - temp;
                    buffer[odd + 1] = buffer[even + 1] - temp2;
                    buffer[even] = buffer[even] + temp;
                    buffer[even + 1] = buffer[even + 1] + temp2;
                }
            }
        }
        const result = new Array(this.size / 2);
        for (let i = 0; i < this.size / 2; i++) {
            result[i] = Math.sqrt(buffer[i * 2] * buffer[i * 2] + buffer[i * 2 + 1] * buffer[i * 2 + 1]);
        }
        return result;
    }
}
export const createSpectralData = (n) => {
    const spectraSize = 1024;
    const timeData = new Array(spectraSize);

    // Generate some random data with spectral components
    for (let i = 0; i < spectraSize; i++) {
        timeData[i] =
            2.0 * Math.sin((2 * Math.PI * i) / (20 + n * 0.2)) +
            5 * Math.sin((2 * Math.PI * i) / (10 + n * 0.01)) +
            10 * Math.sin((2 * Math.PI * i) / (5 + n * -0.002)) +
            2.0 * Math.random();
    }

    // Do a fourier-transform on the data to get the frequency domain
    const transform = new Radix2FFT(spectraSize);
    const yValues = transform.run(timeData).slice(0, 300); // We only want the first N points just to make the example cleaner

    // This is just setting a floor to make the data cleaner for the example
    for (let i = 0; i < yValues.length; i++) {
        yValues[i] =
            yValues[i] < -30 || yValues[i] > -5 ? (yValues[i] < -30 ? -30 : Math.random() * 9 - 6) : yValues[i];
    }
    yValues[0] = -30;

    // we need x-values (sequential numbers) for the frequency data
    const xValues = yValues.map((value, index) => index);

    return { xValues, yValues };
};