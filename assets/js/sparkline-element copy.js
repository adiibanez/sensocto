class SparklineElement extends HTMLElement {
    constructor() {
        super();
       console.log('SparklineElement: constructor called.', this.id);
    }

   connectedCallback() {
         console.log('SparklineElement: connectedCallback called.', this.id);
    }

  disconnectedCallback() {
       console.log('SparklineElement: disconnectedCallback called', this.id)
    }
}

customElements.define('sparkline-element', SparklineElement);