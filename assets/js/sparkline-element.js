import Sparkline2 from '../svelte/Sparkline2.svelte';

class SparklineElement extends HTMLElement {

    static get observedAttributes() {
        return ['data-values', 'data-append', 'width', 'height', 'linewidth'];
    }
    
    constructor() {
        super();
        console.log('SparklineElement: constructor called.', this.id);
        this.container = document.createElement('div');
        this.container.classList.add('sparkline-container');
        this.attachShadow({ mode: 'open' }).appendChild(this.container);

    }
    connectedCallback() {
        console.log('SparklineElement: connectedCallback called.', this.id);
        this._mountComponent();
    }

    _mountComponent = () => {
        try {
            const dataValuesString = this.getAttribute('data-values');
            let initialData = [];

            if (dataValuesString) {
                try {
                    initialData = JSON.parse(dataValuesString);
                } catch (error) {
                    console.warn('SparklineElement: Error parsing data-values attribute:', error);
                }
            } else {
                console.warn("SparklineElement: No data-values attribute, initialiting with empty data array", this.id);
            }

            this.sparkline = new Sparkline2({
                target: this.container,
                props: {
                    data: initialData,
                    id: this.id,
                },
            });
            console.log('SparklineElement: Sparkline component mounted', this.id);
        } catch (error) {
            console.error('SparklineElement: Error mounting Sparkline component:', error);
        }
    }

    disconnectedCallback() {
        if (this.sparkline) {
            console.log('SparklineElement: disconnectedCallback called, destroying component', this.id);
            try {
                this.sparkline.$destroy();
            }
            catch (err) {
                console.error('SparklineElement: Error destroying component', err);
            }
        } else {
            console.warn("SparklineElement: disconnectedCallback called, but component wasn't initialized", this.id);
        }
    }

    attributeChangedCallback(name, oldValue, newValue) {

        console.log("SparklineElement: attribute changed:", name, oldValue, newValue);

        if (name === 'data-values') {
            console.log("SparklineElement: data-values attribute changed:", this.id, " new value:", newValue);
            if (this.sparkline) {
                try {
                    const newData = newValue ? JSON.parse(newValue) : []; // Handle Null
                    this.sparkline.$set({ data: newData });
                    console.log("SparklineElement: data-values updated in component", this.id, " data:", newData);
                } catch (err) {
                    console.error("SparklineElement: Error updating data-values", err, this.id);
                }
            }

        } else if (name === "data-append") {
            console.log("SparklineElement: data-append attribute changed:", this.id, " new value:", newValue);
        }
    }
}

customElements.define('sparkline-element', SparklineElement);