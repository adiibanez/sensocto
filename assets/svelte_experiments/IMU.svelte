<script lang="ts">
    import { run } from "svelte/legacy";

    interface Props {
        imuData?: string;
    }

    let { imuData = "" }: Props = $props();

    let container = $state();

    function debounce(cb, t) {
        let timer;
        return (...args) => {
            clearTimeout(timer);
            timer = setTimeout(() => cb(...args), t);
        };
    }

    run(() => {
        if (imuData) {
            debounce(() => {
                console.log(imuData);
                //handleImuData(imuData)
            }, 1000);
        }
    });

    // renderer
    //container.dataset.imu = JSON.stringify(generateRealisticImuData(20));

    const renderer = new THREE.WebGLRenderer();
    //renderer.setSize(window.innerWidth, window.innerHeight);
    container.appendChild(renderer.domElement);

    // camera
    var camera = new THREE.PerspectiveCamera(
        45,
        window.innerWidth / window.innerHeight,
        1,
        1000,
    );
    camera.position.z = 150;

    // scene
    var scene = new THREE.Scene();
    // cube and axes
    function buildAxis(src, dst, colorHex, dashed) {
        var geom = new THREE.Geometry();
        var mat;

        if (dashed)
            mat = new THREE.LineDashedMaterial({
                linewidth: 3,
                color: colorHex,
                dashSize: 3,
                gapSize: 3,
            });
        else
            mat = new THREE.LineBasicMaterial({
                linewidth: 3,
                color: colorHex,
            });

        geom.vertices.push(src.clone());
        geom.vertices.push(dst.clone());
        geom.computeLineDistances(); // This one is SUPER important, otherwise dashed lines will appear as simple plain lines

        var axis = new THREE.Line(geom, mat, THREE.LinePieces);
        return axis;
    }

    var imuObj = new THREE.Object3D();
    imuObj.add(
        buildAxis(
            new THREE.Vector3(0, 0, 0),
            new THREE.Vector3(100, 0, 0),
            0xff0000,
            false,
        ),
    ); // +X
    imuObj.add(
        buildAxis(
            new THREE.Vector3(0, 0, 0),
            new THREE.Vector3(0, 100, 0),
            0x00ff00,
            false,
        ),
    ); // +Y
    imuObj.add(
        buildAxis(
            new THREE.Vector3(0, 0, 0),
            new THREE.Vector3(0, 0, 100),
            0x0000ff,
            false,
        ),
    ); // +Z
    var cube = new THREE.Mesh(
        new THREE.BoxGeometry(50, 50, 50),
        new THREE.MeshNormalMaterial(),
    );
    cube.overdraw = true;
    imuObj.add(cube);
    scene.add(imuObj);

    function handleImuData(data) {
        if (data && Array.isArray(data) && data.length > 0) {
            let tokens = data.shift().split(",");
            if (tokens.length === 11) {
                imuObj.quaternion.w = parseFloat(tokens[7]);
                imuObj.quaternion.y = parseFloat(tokens[8]);
                imuObj.quaternion.x = -parseFloat(tokens[9]);
                imuObj.quaternion.z = parseFloat(tokens[10]);

                document.getElementById("text").innerHTML =
                    "time = " + tokens[0];
                requestAnimationFrame(function () {
                    renderer.render(scene, camera);
                });
            } else {
                console.warn("Data format invalid");
            }
        } else {
            console.warn("Invalid data format", data);
        }
    }
</script>

<svelte:head>
    <script
        src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r71/three.min.js"
    ></script>
</svelte:head>

{imuData}

<div
    id="container"
    bind:this={container}
    style="width:200px; height: 100px; border:1px solid red"
></div>
